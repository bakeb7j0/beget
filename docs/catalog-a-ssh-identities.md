# Catalog A — SSH Identities

**Status:** `placeholder` — BJ fills in rows before wave-2b (#11) executes.

Materialized form of Dev Spec R-17: the SSH private keys that `chezmoi apply`
materializes under `~/.ssh/`. One row per identity. Agents implementing #11
read this file; they do not infer or invent entries.

## Schema

| Field | Meaning |
|---|---|
| **Identity name** | Short name used throughout (e.g. `id_ed25519`, `blueshift_dev`). Also the base name of the private-key file under `~/.ssh/`. |
| **Template file** | Path under `dot_ssh/` in the chezmoi source tree, ending `.tmpl`. E.g. `private_id_ed25519.tmpl`. |
| **VW item** | Vaultwarden item name that stores the private key. Convention: `ssh-<identity>`. |
| **Key type** | `ed25519`, `rsa-4096`, etc. Drives any `ssh-keygen` helper logic. |
| **Host block** | The `Host` line (or alias list) in `~/.ssh/config` this key pairs with. |
| **Match pattern** | The `HostName` / `Host` glob that routes traffic to this key (e.g. `github.com`, `gitlab.analogic.com`, `*.blueshift-dev.internal`). |
| **Purpose** | One-line description of what the key is for. Optional but recommended. |

## Identities

<!--
  Fill in concrete rows below. Remove the TODO(BJ) markers when complete.
  When this table has no TODO(BJ) rows, flip Status above to `filled`.
-->

| Identity | Template file | VW item | Key type | Host block | Match pattern | Purpose |
|---|---|---|---|---|---|---|
| `id_ed25519`            | `private_id_ed25519.tmpl`            | `ssh-id-ed25519`            | ed25519 | TODO(BJ) | TODO(BJ) | Default personal key |
| `blueshift_dev`         | `private_blueshift_dev.tmpl`         | `ssh-blueshift-dev`         | TODO(BJ) | TODO(BJ) | TODO(BJ) | Blueshift dev env |
| `blueshift_test`        | `private_blueshift_test.tmpl`        | `ssh-blueshift-test`        | TODO(BJ) | TODO(BJ) | TODO(BJ) | Blueshift test env |
| `blueshift_prod`        | `private_blueshift_prod.tmpl`        | `ssh-blueshift-prod`        | TODO(BJ) | TODO(BJ) | TODO(BJ) | Blueshift prod env |
| `analogic_gitlab`       | `private_analogic_gitlab.tmpl`       | `ssh-analogic-gitlab`       | TODO(BJ) | TODO(BJ) | TODO(BJ) | Analogic GitLab |
| `waveeng_gitlab`        | `private_waveeng_gitlab.tmpl`        | `ssh-waveeng-gitlab`        | TODO(BJ) | TODO(BJ) | TODO(BJ) | Wave Engineering GitLab |

## `~/.ssh/config` ordering

`~/.ssh/config` matches first-win per block. Order rows in `config.tmpl`
most-specific-first: explicit hostname blocks before wildcards, wildcards
before the `Host *` default. Agents implementing #11 should preserve the
order declared in the table above.

## Adding a new identity

1. Append a row above.
2. Create `dot_ssh/private_<identity>.tmpl` that renders the VW item's `privateKey` field.
3. Update `dot_ssh/config.tmpl` with the matching `Host` block.
4. Add a row to the corresponding public-key catalog (if one exists) so `authorized_keys` entries stay in sync.
5. Flip **Status** back to `placeholder` if the row is TODO until rotated in.

## Out of scope

- Public keys / `authorized_keys` (separate concern; may get its own catalog).
- Known-hosts pinning (separate theme).
- Signing keys for git commits (Catalog elsewhere if ever introduced).
