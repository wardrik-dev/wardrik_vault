defmodule WardrikVault do
  @moduledoc """
  A vault keeps credentials sealed in a `WardrikStore`, and gives them to a WardrikCore agent's tools.

      children = [
        {WardrikStore, store},
        {WardrikVault, name: MyApp.Vault, store: store, keys: [System.fetch_env!("VAULT_KEY")]}
      ]

      WardrikCore.start_agent(agent_id: "digest", model: "...", credentials: {WardrikVault, MyApp.Vault})
  """

  @behaviour WardrikCore.Credentials

  use GenServer

  require Logger

  alias WardrikCore.Principal
  alias WardrikVault.Sealed

  @typedoc "A vault, by the name your app gave it."
  @type t() :: atom()

  @typedoc "A secret someone put in, or a grant someone gave by authorizing."
  @type kind() :: :secret | :grant

  @doc "Starts the vault. Takes `:name`, `:store`, `:keys`, and `:grants` as `{module, opts}`."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    opts = Keyword.validate!(opts, [:name, :store, keys: [], grants: nil])
    GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))
  end

  @doc "Seals `value` as `name` for `principal`. Takes `kind:` and `if_vsn:`."
  @spec put(t(), Principal.t(), String.t(), binary(), kind: kind(), if_vsn: WardrikStore.vsn()) ::
          {:ok, WardrikStore.vsn()} | {:error, term()}
  def put(vault, %Principal{} = principal, name, value, opts \\ []) when is_binary(value) do
    {kind, opts} = Keyword.pop(opts, :kind, :secret)
    %{store: store, keys: keys} = settings(vault)
    path = path(principal, name)

    case keys do
      [key | _rest] -> WardrikStore.put(store, path, Sealed.seal(key, path, kind, value), opts)
      [] -> {:error, :no_key}
    end
  end

  @doc "Unseals what `principal` holds as `name`."
  @spec fetch(t(), Principal.t(), String.t()) :: {:ok, binary()} | {:error, term()}
  def fetch(vault, principal, name) do
    case lookup(vault, principal, name) do
      {:ok, _kind, value, _vsn} -> {:ok, value}
      {:error, _kind, reason} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Unseals what `principal` holds as `name`, with its kind and version."
  @spec lookup(t(), Principal.t(), String.t()) ::
          {:ok, kind(), binary(), WardrikStore.vsn()}
          | {:error, term()}
          | {:error, kind(), term()}
  def lookup(vault, %Principal{} = principal, name) do
    %{store: store, keys: keys} = settings(vault)
    path = path(principal, name)

    with :ok <- has_keys(keys),
         {%Sealed{} = sealed, vsn} <- WardrikStore.lookup(store, path) do
      unsealed(Sealed.unseal(sealed, keys, path), sealed.kind, vsn)
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Removes what `principal` holds as `name`. Removing nothing is `:ok`."
  @spec delete(t(), Principal.t(), String.t()) :: :ok | {:error, term()}
  def delete(vault, %Principal{} = principal, name),
    do: vault |> settings() |> Map.fetch!(:store) |> WardrikStore.delete(path(principal, name))

  @doc "Lists the names `principal` holds. Reads no credential and needs no key."
  @spec names(t(), Principal.t()) :: [String.t()]
  def names(vault, %Principal{} = principal) do
    vault
    |> list()
    |> Enum.filter(fn {id, _name, _kind} -> id == principal.id end)
    |> Enum.map(fn {_id, name, _kind} -> name end)
  end

  @doc "Lists every credential as `{principal_id, name, kind}`. Reads no credential and needs no key."
  @spec list(t()) :: [{String.t(), String.t(), kind()}]
  def list(vault) do
    %{store: store} = settings(vault)

    store
    |> WardrikStore.keys()
    |> Enum.flat_map(fn path -> listed(store, path) end)
  end

  @doc "Returns a new key, base64-encoded, for `:keys`."
  @spec generate_key() :: String.t()
  defdelegate generate_key, to: Sealed

  @impl WardrikCore.Credentials
  def resolve(_name, nil, _vault), do: {:error, :no_principal}

  def resolve(name, principal, vault) do
    case lookup(vault, principal, name) do
      {:ok, :secret, value, _vsn} ->
        {:ok, value}

      {:ok, :grant, value, vsn} ->
        grants(vault, :renew, [name, principal, %{value: value, vsn: vsn}])

      {:error, :not_found} ->
        grants(vault, :ask, [name, principal])

      {:error, :grant, reason} ->
        ask_again(vault, name, principal, reason)

      {:error, _kind, reason} ->
        {:error, reason}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl WardrikCore.Credentials
  def refused(_name, nil, _vault), do: :ok

  def refused(name, principal, vault) do
    case lookup(vault, principal, name) do
      {:ok, :grant, _value, _vsn} -> grants(vault, :refused, [name, principal])
      _secret_or_none -> :ok
    end
  end

  @impl GenServer
  def init(opts) do
    keys = Keyword.fetch!(opts, :keys)
    decoded = Sealed.decode_keys(keys)
    if length(decoded) < length(keys), do: Logger.warning("A vault key isn't 32 bytes of base64")

    settings = %{
      store: opts |> Keyword.fetch!(:store) |> WardrikStore.scope("wardrik_vault"),
      keys: decoded,
      grants: Keyword.fetch!(opts, :grants)
    }

    table =
      :ets.new(table(Keyword.fetch!(opts, :name)), [
        :named_table,
        :protected,
        read_concurrency: true
      ])

    true = :ets.insert(table, {:settings, settings})
    {:ok, table}
  end

  defp settings(vault) do
    [{:settings, settings}] = :ets.lookup(table(vault), :settings)
    settings
  rescue
    ArgumentError ->
      reraise ArgumentError,
              "#{inspect(vault)} isn't started. Add {WardrikVault, name: #{inspect(vault)}, store: store, keys: keys} to your supervision tree, ahead of what uses it.",
              __STACKTRACE__
  end

  defp table(vault), do: Module.concat(vault, "Settings")

  defp has_keys([]), do: {:error, :no_key}
  defp has_keys(_keys), do: :ok

  defp unsealed({:ok, value}, kind, vsn), do: {:ok, kind, value, vsn}
  defp unsealed({:error, reason}, kind, _vsn), do: {:error, kind, reason}

  defp ask_again(vault, name, principal, reason) do
    Logger.warning(
      "#{name} for #{principal.id} can't be unsealed (#{inspect(reason)}), so asking again"
    )

    grants(vault, :ask, [name, principal])
  end

  defp grants(vault, callback, args) do
    case settings(vault).grants do
      {module, opts} -> apply(module, callback, [vault | args] ++ [opts])
      nil -> nothing_granted(callback)
    end
  end

  defp nothing_granted(:refused), do: :ok
  defp nothing_granted(_renew_or_ask), do: {:error, :not_found}

  defp listed(store, path) do
    case {String.split(path, "/"), WardrikStore.lookup(store, path)} do
      {[id, name], {%Sealed{kind: kind}, _vsn}} -> [{decode(id), decode(name), kind}]
      _other -> []
    end
  end

  defp path(%Principal{id: id}, name) when is_binary(name), do: encode(id) <> "/" <> encode(name)

  defp encode(segment), do: URI.encode_www_form(segment)
  defp decode(segment), do: URI.decode_www_form(segment)
end
