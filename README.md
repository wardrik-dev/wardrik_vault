# WardrikVault

Credentials sealed at rest, for [WardrikCore](https://hexdocs.pm/wardrik_core) agents to call tools
with.

## Install

```elixir
def deps do
  [
    {:wardrik_vault, "~> 0.1"}
  ]
end
```

## Start a vault

The vault keeps its credentials in a [WardrikStore](https://hexdocs.pm/wardrik_store). Start it
after the store, with a name and its keys:

```elixir
children = [
  {WardrikStore, store},
  {WardrikVault, name: MyApp.Vault, store: store, keys: [System.fetch_env!("VAULT_KEY")]}
]
```

Make a key with `WardrikVault.generate_key/0`. Values are sealed with AES-256-GCM. The first key
seals, and any of them unseals. To rotate, put a new key first, and keep the old one behind it until
nothing needs it. Without a key, nothing is sealed or unsealed.

## Put credentials in

A credential belongs to a `WardrikCore.Principal`, by its `id`:

```elixir
jon = %WardrikCore.Principal{id: "user:jon"}

{:ok, _vsn} = WardrikVault.put(MyApp.Vault, jon, "github", "ghp_...")
WardrikVault.fetch(MyApp.Vault, jon, "github")
#=> {:ok, "ghp_..."}
WardrikVault.list(MyApp.Vault)
#=> [{"user:jon", "github", :secret}]
```

`list/1` and `names/2` read no credential and need no key. The vault seals values, not names, so
anyone who can read the store can see who holds a credential of which name.

## Give it to agents

The vault is a `WardrikCore.Credentials`. Give an agent the vault's name:

```elixir
WardrikCore.start_agent(
  agent_id: "digest",
  model: "anthropic:claude-haiku-4-5",
  principal: jon,
  credentials: {WardrikVault, MyApp.Vault}
)
```

The agent's saved state holds only that name, never a key. A tool's call reads what the principal
it acts for holds, and nothing else. Nothing falls back from a person to their org, so give an
agent that works for your org a principal of its own.

## Grants

A grant is a credential someone gives by authorizing an account, like an OAuth token. Give the
vault a `WardrikVault.Grants` module to handle them:

```elixir
{WardrikVault, name: MyApp.Vault, store: store, keys: keys, grants: {MyApp.OAuth, opts}}
```

When a tool needs a grant, the vault hands it to the module to renew. When nobody holds the name,
the vault asks the module, which answers with a URL to authorize at, and the tool's call parks
there. The module writes what it gets back with `put/5` and `kind: :grant`. Pass `if_vsn:` so two
renewals never write over each other.
