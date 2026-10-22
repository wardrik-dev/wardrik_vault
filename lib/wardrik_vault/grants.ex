defmodule WardrikVault.Grants do
  @moduledoc """
  Grants are credentials a principal gives by authorizing an account, like an OAuth token.

  The vault keeps a grant sealed like any secret, and hands it to the grants module you give it as
  `grants: {module, opts}`. That module renews a grant that has run out, and asks a principal to
  authorize a name nobody holds. It writes what it gets back with `WardrikVault.put/5` and
  `kind: :grant`, and the vault never reads inside it.
  """

  alias WardrikCore.Principal

  @typedoc "A grant as the vault holds it, with the version to write a renewal over."
  @type grant() :: %{value: binary(), vsn: WardrikStore.vsn()}

  @doc "Returns the credential `grant` gives, renewing it first when it has run out."
  @callback renew(GenServer.name(), String.t(), Principal.t(), grant(), opts :: term()) ::
              {:ok, term()} | {:authorize, String.t()} | {:error, term()}

  @doc "Asks the principal to authorize `name`, or returns `{:error, :not_found}` when it can't."
  @callback ask(GenServer.name(), String.t(), Principal.t(), opts :: term()) ::
              {:authorize, String.t()} | {:error, term()}

  @doc "Hears that a service refused the grant held as `name`."
  @callback refused(GenServer.name(), String.t(), Principal.t(), opts :: term()) :: :ok
end
