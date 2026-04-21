# Catalog A — SSH Identities

**Status:** `filled` (backfilled 2026-04-20 from `~/sysadmin/unresolved-issues/beget-sketchbook.md` §A).

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

Identity names follow the sketchbook's planned rename scheme: `id_ed25519_<scope>`.
This keeps the key type visible in the filename and makes future rotations
(e.g. moving the legacy RSA key — see footnote) mechanical.

**Source provenance (important for #11 agents — do not re-derive from malory today):**

- **Identity names** come from sketchbook §"SSH architecture" / keys list (lines
  230-234 of `~/sysadmin/unresolved-issues/beget-sketchbook.md`) plus the rename
  plan in §A "SSH keys and identities" (lines 375-389).
- **Host blocks and match patterns for blueshift rows** come from the sketchbook's
  planned `~/.ssh/config` example (lines 240-253), not from malory's current
  `~/.ssh/config`. Malory currently uses literal host aliases (`perkollate-dev`,
  `perkollate-test`, `perkollate-prod`); the beget-managed config migrates to
  wildcard-domain matching as documented in the sketchbook. Agents should emit
  the wildcard form shown here, not the legacy aliases.
- **Host blocks for GitLab rows** match today's malory config exactly
  (`gitlab.com` literal, and the `gitlab-waveeng` alias that points at
  `gitlab.com` with its own key).

| Identity | Template file | VW item | Key type | Host block | Match pattern | Purpose |
|---|---|---|---|---|---|---|
| `id_ed25519`                      | `private_id_ed25519.tmpl`                      | `ssh-id-ed25519`                      | ed25519 | `Host *`                    | `*` (catch-all default) | Primary personal identity (homelab SSH, general) |
| `id_ed25519_analogic_gitlab`      | `private_id_ed25519_analogic_gitlab.tmpl`      | `ssh-id-ed25519-analogic-gitlab`      | ed25519 | `Host gitlab.com`           | `gitlab.com`            | Analogic GitLab identity (renamed from `gitlab.id_ed25519`) |
| `id_ed25519_waveeng_gitlab`       | `private_id_ed25519_waveeng_gitlab.tmpl`       | `ssh-id-ed25519-waveeng-gitlab`       | ed25519 | `Host gitlab-waveeng`       | `gitlab-waveeng` (alias → `gitlab.com`) | Personal / Oak & Wave GitLab identity (renamed from `gitlab-waveeng.id_ed25519`) |
| `id_ed25519_blueshift_dev`        | `private_id_ed25519_blueshift_dev.tmpl`        | `ssh-id-ed25519-blueshift-dev`        | ed25519 | `Host *.dev.blueshift.plus` | `*.dev.blueshift.plus`  | Blueshift dev env (renamed from `perkollate-dev`) |
| `id_ed25519_blueshift_test`       | `private_id_ed25519_blueshift_test.tmpl`       | `ssh-id-ed25519-blueshift-test`       | ed25519 | `Host *.test.blueshift.plus`| `*.test.blueshift.plus` | Blueshift test env (renamed from `perkollate-test`) |
| `id_ed25519_blueshift_prod`       | `private_id_ed25519_blueshift_prod.tmpl`       | `ssh-id-ed25519-blueshift-prod`       | ed25519 | `Host *.blueshift.plus`     | `*.blueshift.plus` — **greedy; must come last among blueshift rules** | Blueshift prod env (renamed from `perkollate-prod`) |

**Footnote — `id_rsa` rotation (not in this catalog).** Malory currently has a
legacy `~/.ssh/id_rsa` (RSA) paired with the `blueshift-dev` host block
(3.214.20.90). The sketchbook flags this as "TODO: rotate to ed25519?" — a
separate concern tracked outside this catalog. When rotated, it'll either
replace `id_ed25519_blueshift_dev` (if same host) or get its own row.

## `~/.ssh/config` ordering

`~/.ssh/config` matches first-win per block. Order rows in `config.tmpl`
most-specific-first:

1. Explicit hostnames and aliases (`gitlab.com`, `gitlab-waveeng`).
2. Narrow wildcards (`*.dev.blueshift.plus`, `*.test.blueshift.plus`).
3. **Greedy wildcards last** — `*.blueshift.plus` matches everything under
   `blueshift.plus` including `*.dev.` and `*.test.`, so it must come after
   the narrower dev/test blocks or it shadows them.
4. `Host *` catch-all default at the very end.

Agents implementing #11 should preserve the order declared in the table above.

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
