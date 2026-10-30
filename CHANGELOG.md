# Changelog

## 0.1.0-rc.1 (2026-10-30)

- `WardrikVault`, which keeps credentials sealed at rest with AES-256-GCM, in a `WardrikStore`.
- Keys that rotate: the first seals, any unseals.
- Credentials held by each `WardrikCore.Principal`. A tool reads only what its turn's principal
  holds.
- The vault as an agent's `WardrikCore.Credentials`. Its saved state holds only the vault's name.
- The deployment's own secrets, named in options as `{:secret, name}` and read on each use.
- Grants, like OAuth tokens, renewed or asked for through a `WardrikVault.Grants` module.
