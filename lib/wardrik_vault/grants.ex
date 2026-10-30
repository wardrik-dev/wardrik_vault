defmodule WardrikVault.Grants do
  @moduledoc """
  The behaviour for grants: credentials a principal gives by authorizing an account, like OAuth
  tokens.

      {WardrikVault, name: MyApp.Vault, store: store, keys: keys, grants: {MyApp.OAuth, opts}}

  When a tool needs a credential, the vault calls:

    * `c:renew/5` if the principal holds it as a grant.
    * `c:ask/4` if nobody holds it, or the grant won't unseal.
    * `c:refused/4` when a service refuses the grant.

  Each callback gets the vault's name first and the module's `opts` last.

  Write what comes back from authorizing with `WardrikVault.put/5` and `kind: :grant`. Pass
  `:if_vsn` so two renewals never write over each other.
  """

  alias WardrikCore.Principal

  @typedoc "A grant as the vault holds it. `vsn` is the version to write a renewal over."
  @type grant() :: %{value: binary(), vsn: WardrikStore.vsn()}

  @doc "Returns the credential `grant` gives. Renews it first if it has run out."
  @callback renew(GenServer.name(), String.t(), Principal.t(), grant(), opts :: term()) ::
              {:ok, term()} | {:authorize, String.t()} | {:error, term()}

  @doc "Returns `{:authorize, url}` for the principal to authorize `name` at, or `{:error, :not_found}`."
  @callback ask(GenServer.name(), String.t(), Principal.t(), opts :: term()) ::
              {:authorize, String.t()} | {:error, term()}

  @doc "Called when a service refuses the grant held as `name`."
  @callback refused(GenServer.name(), String.t(), Principal.t(), opts :: term()) :: :ok
end
