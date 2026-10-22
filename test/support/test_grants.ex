defmodule WardrikVault.TestGrants do
  @moduledoc "Grants the tests give a vault: each callback tells the test, and answers as told."
  @behaviour WardrikVault.Grants

  @impl WardrikVault.Grants
  def renew(_vault, name, _principal, grant, test) do
    send(test, {:renew, name, grant})
    {:ok, "renewed " <> grant.value}
  end

  @impl WardrikVault.Grants
  def ask(_vault, name, principal, test) do
    send(test, {:ask, name, principal.id})
    {:authorize, "https://example.com/authorize/#{name}"}
  end

  @impl WardrikVault.Grants
  def refused(_vault, name, _principal, test) do
    send(test, {:refused, name})
    :ok
  end
end
