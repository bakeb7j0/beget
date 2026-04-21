# beget — Operations Runbook

Step-by-step procedures for every normative flow in `docs/beget-devspec.md` §4.
Every command in this document is copy-pasteable as-is. Placeholders are
wrapped in `<angle-brackets>`.

If a command fails, check the matching entry in [Troubleshooting](#troubleshooting) before retrying.

For acceptance verification — especially on a fresh VM or after a major
change — pair each runbook section with the corresponding procedure in
[Manual Verification Procedures](manual-verification.md) (MV-01..MV-10).

---

## Table of Contents

1. [Fresh Machine Bootstrap](#1-fresh-machine-bootstrap) — Dev Spec §4.2
2. [Ongoing Sync](#2-ongoing-sync) — Dev Spec §4.3
3. [Secret Rotation](#3-secret-rotation) — Dev Spec §4.4
4. [Adding a New Secret](#4-adding-a-new-secret) — Dev Spec §4.5
5. [Activity Context Switch](#5-activity-context-switch) — Dev Spec §4.6
6. [Offline Operation](#6-offline-operation) — Dev Spec §4.7
7. [Migrating Secrets from `~/.secrets/`](#7-migrating-secrets-from-secrets) — S2.5
8. [Key Rotation (SSH / AWS)](#8-key-rotation-ssh--aws)
9. [Role Change](#9-role-change)
10. [Adding a New Machine](#10-adding-a-new-machine)
11. [Adding a New Context](#11-adding-a-new-context)
12. [Troubleshooting](#troubleshooting)

---

## 1. Fresh Machine Bootstrap

**Dev Spec reference**: §4.2 Fresh Machine Bootstrap (primary flow).

**Preconditions**
- Ubuntu 24.04+ or RHEL 9+/family (Fedora, Rocky, Alma).
- Network access to `github.com` and the Vaultwarden host.
- Vaultwarden master password memorized.
- A user account with `sudo` (not root — installer refuses `--allow-root` by default).

**Commands**

```bash
# One-liner entry point:
curl -fsSL https://github.com/bakeb7j0/beget/raw/HEAD/install.sh | bash -s -- --role=workstation
```

Expected output (abridged):

```
[install] beget bootstrap starting
[install] OS: ubuntu 24.04 — supported
[install] installing prerequisites: chezmoi rbw direnv pinentry-curses git curl
...
[install] running: chezmoi init https://github.com/bakeb7j0/beget --data role=workstation
[install] chezmoi apply complete
[install] done. Open a new terminal for all changes to take effect.
```

**Post-condition check** — run the [Deployment Verification Checklist](deployment-verification.md).

**Troubleshooting**: see [rbw locked](#rbw-locked), [Vaultwarden unreachable](#vaultwarden-unreachable), [chezmoi conflicts](#chezmoi-conflicts).

---

## 2. Ongoing Sync

**Dev Spec reference**: §4.3 Ongoing Sync.

**Preconditions**: beget already bootstrapped; rbw unlocked (or at least logged in and reachable).

**Commands**

```bash
# Refresh dotfiles + run_onchange scripts + secret templates:
chezmoi update

# Equivalent long form if you need to see each step:
chezmoi git pull
chezmoi apply --verbose
```

Expected output: per-file `identical`, `updated`, or `skipped` lines. No red errors.

Re-materialize secrets from VW after rotating them remotely:

```bash
rbw sync
chezmoi apply
```

---

## 3. Secret Rotation

**Dev Spec reference**: §4.4 Secret Rotation.

**Preconditions**: You've already updated the secret's value in Vaultwarden via the web UI or `rbw edit`.

**Commands**

```bash
# Pull the new value to the local rbw cache:
rbw sync

# File-shaped secrets (SSH keys, AWS credentials) — re-render:
chezmoi apply

# Env-var secrets (GITHUB_PAT, GITLAB_TOKEN, BAO_TOKEN) — refreshed
# on the next wrapper call:
gh auth status   # picks up the new GITHUB_PAT
```

Expected output: no errors from `rbw sync`; `chezmoi apply` shows updated file hashes for rotated items.

---

## 4. Adding a New Secret

**Dev Spec reference**: §4.5 Adding a New Secret. See also S2.4 (`newsecret`).

**Preconditions**: rbw unlocked.

**Commands**

```bash
newsecret <item-name>
# Example:
newsecret github-pat
```

`newsecret` prompts for the value on stdin (or accepts a piped value), creates a Vaultwarden Login item with the same name, and prints the derived env-var name (`github-pat` → `$GITHUB_PAT`).

Expected output:

```
[newsecret] created Vaultwarden item: github-pat
[newsecret] use via: secret GITHUB_PAT  (or $(secret_get github-pat))
```

---

## 5. Activity Context Switch

**Dev Spec reference**: §4.6 Activity Context Switch (direnv).

**Preconditions**:
- `direnv` installed and the hook active in your shell (R-27). Verify: `type direnv_hook` returns a function.
- A `.envrc` file placed in the context-scoped directory.

**One-time setup** (first time entering a new context tree):

```bash
cd ~/sandbox/analogic
cp ~/.local/share/beget/envrc.analogic.example ./.envrc
direnv allow
```

Expected output after `direnv allow`:

```
direnv: loading ~/sandbox/analogic/.envrc
direnv: export +AWS_PROFILE +BEGET_CONTEXT +GITLAB_TOKEN
```

**Normal use**:

```bash
cd ~/sandbox/analogic        # direnv loads
echo "$BEGET_CONTEXT"        # → analogic
glab mr list                 # uses GITLAB_TOKEN from rbw
cd ~                         # direnv unloads
echo "${BEGET_CONTEXT:-unset}"  # → unset
```

**Troubleshooting**: see [direnv not authorized](#direnv-not-authorized).

---

## 6. Offline Operation

**Dev Spec reference**: §4.7 Offline Operation.

**Already-bootstrapped machine, going offline**

- `rbw get <item>` continues to work from the local cache at `~/.cache/rbw/`.
- New secrets added during the outage will not propagate until reconnect + `rbw sync`.

**Fresh bootstrap without network to Vaultwarden**

```bash
curl -fsSL https://github.com/bakeb7j0/beget/raw/HEAD/install.sh | bash -s -- --role=workstation --skip-secrets
```

The machine gets base packages, dotfiles, and scripts, but no SSH keys / AWS creds. On reconnect:

```bash
rbw login
rbw sync
chezmoi apply
```

---

## 7. Migrating Secrets from `~/.secrets/`

**Implements**: S2.5 (bakeb7j0/beget#14).

**Preconditions**: rbw unlocked. Source files in `~/.secrets/` (or `~/secrets/`).

**Dry run first — always**

```bash
scripts/migrate-secrets.sh --dry-run
```

Expected output: one `would create <name>` line per file; `migrated=N skipped=0 failed=0`.

**Live run**

```bash
scripts/migrate-secrets.sh
```

Each file becomes a VW Login item with the filename as the item name and the file contents as the password. sha256 is verified on read-back. Source files are **not** deleted automatically.

**After a successful run**

```bash
# Verify at least one migrated secret is accessible:
rbw get <one-of-the-names>

# After visual inspection, delete the plaintext source files manually:
rm -ri ~/.secrets/
```

**Troubleshooting**: see [rbw locked](#rbw-locked) (exit 2) and [migration sha256 mismatch](#migration-sha256-mismatch) (exit 3).

---

## 8. Key Rotation (SSH / AWS)

**SSH key rotation**

```bash
# 1. Generate the new key locally (not committed):
ssh-keygen -t ed25519 -f /tmp/new_key -N ''

# 2. Paste the private key into rbw, replacing the existing VW item:
rbw edit <ssh-item-name>   # (delete old, paste new, save)
# OR, if replacing whole-cloth:
rbw rm <ssh-item-name> && newsecret <ssh-item-name> </tmp/new_key

# 3. Publish the PUBLIC key to the remote host (GitHub/GitLab/your server)
# BEFORE the next step — otherwise you lock yourself out.

# 4. Re-materialize on this machine:
chezmoi apply

# 5. Test:
ssh -T git@github.com   # or the relevant host

# 6. Clean up:
shred -u /tmp/new_key
```

**AWS credential rotation**

```bash
# 1. Rotate in AWS console or via `aws iam create-access-key`.

# 2. Update the matching VW item (aws-<profile>-access-key-id,
#    aws-<profile>-secret-access-key). See docs/catalog-b-aws-profiles.md
#    for the canonical item names.
rbw edit aws-default-access-key-id
rbw edit aws-default-secret-access-key

# 3. Re-render ~/.aws/credentials:
chezmoi apply

# 4. Test:
aws sts get-caller-identity --profile default
```

---

## 9. Role Change

Switching a machine from `workstation` to `server` (or vice-versa) changes which
templates and packages apply.

```bash
# Re-init with the new role tag:
chezmoi init --force https://github.com/bakeb7j0/beget --data 'role=server'
chezmoi apply
```

`--force` re-applies source-tree config; existing rendered files are
re-evaluated against the new role data.

---

## 10. Adding a New Machine

Same as §4.2 ([Fresh Machine Bootstrap](#1-fresh-machine-bootstrap)). Before
running, make sure:

- The machine appears in `docs/catalog-a-ssh-identities.md` if it will hold
  any long-lived SSH identities.
- If it's a non-workstation role, pass `--role=<tag>` to the installer.

---

## 11. Adding a New Context

A "context" is a directory tree that should auto-load its own credentials
when you `cd` into it (e.g., an Analogic tree, a blueshift tree).

```bash
# 1. Create the context's secrets in Vaultwarden, naming them per the
#    <context>-<service>-<kind> convention:
newsecret <context>-gitlab-token
newsecret <context>-aws-access-key-id
newsecret <context>-aws-secret-access-key

# 2. Copy the Analogic example .envrc as a starting point and adapt:
mkdir -p ~/sandbox/<context>
cp ~/.local/share/beget/envrc.analogic.example ~/sandbox/<context>/.envrc
$EDITOR ~/sandbox/<context>/.envrc
# Replace all "analogic" references with the new context name.

# 3. Authorize:
cd ~/sandbox/<context>
direnv allow
```

If the context also needs a per-context git identity (e.g., a separate email),
add an `[includeIf "hasconfig:remote.*.url:<pattern>"]` block to
`dot_gitconfig.tmpl` (see Dev Spec §5 and dot_gitconfig-analogic for the
pattern).

---

## Troubleshooting

### rbw locked

**Symptom**: Any `rbw <subcommand>` or a wrapper like `gh` refuses with
`rbw: vault is locked`. `migrate-secrets.sh` exits with code `2` and prints:
`rbw is locked or Vaultwarden is unreachable.`

**Fix**:

```bash
rbw unlock
# then retry the original command
```

If `rbw unlock` itself fails, fall through to [Vaultwarden unreachable](#vaultwarden-unreachable).

### Vaultwarden unreachable

**Symptom**: `rbw sync` or `rbw unlock` hangs or errors with a network
message.

**Fix**:

```bash
# Check connectivity to the VW host:
curl -fsSL https://<your-vaultwarden-host>/alive

# Check rbw config:
rbw config show

# If the cache is fresh, you may keep reading existing secrets offline:
rbw get <item-name>   # works against ~/.cache/rbw/ without network
```

If the cache is stale, see [Offline Operation](#6-offline-operation).

### chezmoi conflicts

**Symptom**: `chezmoi apply` reports `would overwrite modified file` or
similar.

**Fix**:

```bash
# Inspect the diff:
chezmoi diff <path>

# If your local change was intentional, save it and re-apply:
cp <dotfile> ~/tmp-save
chezmoi apply --force
# then reconcile ~/tmp-save manually

# If the template is wrong, edit it in the chezmoi source:
chezmoi edit <path>   # or edit directly in the beget repo checkout
chezmoi apply
```

### direnv not authorized

**Symptom**: Entering a directory prints
`direnv: error ~/sandbox/<ctx>/.envrc is blocked. Run 'direnv allow' to approve its content`.

**Fix**:

```bash
cd ~/sandbox/<ctx>
cat ./.envrc      # inspect first — direnv runs arbitrary shell
direnv allow
```

After a modification to `.envrc`, direnv requires a fresh `direnv allow`.

### migration sha256 mismatch

**Symptom**: `scripts/migrate-secrets.sh` reports
`<name> exists in VW but sha256 differs` and exits `3`.

**Cause**: A VW item with the same name already exists but its content does
not match the source file.

**Fix** (manual — the script deliberately does not overwrite):

```bash
# 1. Inspect both values:
rbw get <name>              # VW's version
cat ~/.secrets/<name>       # the source version

# 2. Decide which is authoritative. If VW wins, the source is stale; delete
#    the source file. If the source wins:
rbw edit <name>
# paste the new value, save, then re-run migrate-secrets.sh
```

---

## See Also

- `docs/beget-devspec.md` — full Dev Spec (authoritative).
- `docs/catalog-a-ssh-identities.md` — SSH key inventory.
- `docs/catalog-b-aws-profiles.md` — AWS profile inventory.
- `docs/deployment-verification.md` — post-install checks.
