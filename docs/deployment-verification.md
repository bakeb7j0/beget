# beget — Deployment Verification Checklist

Run this checklist after every bootstrap (MV-01) and after any significant
`chezmoi apply` to confirm the environment is healthy. Each item specifies
an exact command and the expected output shape.

Copy-paste this entire document into a fresh PR / issue description to
record the results of a verification run.

---

## Section A — Shell

### A1. `~/.bashrc` sources the beget drop-in loader

```bash
grep -E '\.bashrc\.d|bashrc_d' ~/.bashrc
```

Expected: at least one line referencing `~/.bashrc.d/` being iterated
(the loader installed by beget).

- [ ] Pass — matching line present

### A2. PATH order has `~/.local/bin` first

```bash
echo "$PATH" | tr ':' '\n' | head -3
```

Expected: `~/.local/bin` appears before `/usr/bin` and `/usr/local/bin` (R-39).

- [ ] Pass — `~/.local/bin` precedes system bins

### A3. zoxide `z` command is registered (if workstation role)

```bash
type z 2>&1 | head -1
```

Expected (when `zoxide` is installed): `z is a function`. Skippable on
minimal / server roles.

- [ ] Pass / [ ] N/A (role doesn't install zoxide)

### A4. direnv hook is active

```bash
type _direnv_hook 2>&1 | head -1
# (on some direnv versions the hook is named _direnv_export or direnv_hook)
env | grep -i '^DIRENV' || echo 'no-direnv-env'
```

Expected: a function definition for the direnv hook and no error. The
`env | grep DIRENV` line is for context — empty is fine outside a loaded
`.envrc` tree.

- [ ] Pass — direnv hook function defined

---

## Section B — Tools

### B1. chezmoi resolves the beget source tree

```bash
chezmoi source-path
```

Expected: `/home/<user>/.local/share/chezmoi` (or the configured source).
The directory should be a clone of `bakeb7j0/beget`.

- [ ] Pass — source path present and is the beget checkout

### B2. `chezmoi verify` reports no drift

```bash
chezmoi verify
echo "exit=$?"
```

Expected: `exit=0` and no output. Any output lists drifted paths; investigate
before proceeding.

- [ ] Pass — `exit=0`, zero drift

### B3. rbw is logged in and can read an item

```bash
rbw status
# Pick any known item name from your VW — the command should print content.
rbw get test-item 2>&1 || echo 'item missing (expected if test-item never created)'
```

Expected: `rbw status` prints `Logged in. Vault is unlocked.` (or similar —
wording varies by rbw version). The `rbw get` for a real item should succeed.

- [ ] Pass — rbw logged in, unlocked, and can fetch

### B4. Secret wrappers fire on demand

```bash
# Force-clear and re-materialize GITHUB_PAT via the wrapper:
unset GITHUB_PAT
gh auth status 2>&1 | head -5
```

Expected: `gh` works (no "no token found" error). This proves
`secret GITHUB_PAT` materialized inside the `gh()` wrapper (R-16).

- [ ] Pass — `gh auth status` shows an authenticated token

### B5. `newsecret` is on PATH

```bash
command -v newsecret
```

Expected: `/home/<user>/.local/bin/newsecret` (or the $HOME-prefixed path).

- [ ] Pass — `newsecret` resolves

---

## Section C — Secrets

### C1. SSH keys are materialized with correct permissions

```bash
ls -l ~/.ssh/id_ed25519* 2>&1 | head -10
```

Expected: private keys (`id_ed25519*` without `.pub`) are mode `-rw-------`
(`600`). Public keys are mode `-rw-r--r--`. No "No such file" for the
identities listed in `docs/catalog-a-ssh-identities.md` as always-materialized.

- [ ] Pass — private keys are `0600`, public keys are `0644`

### C2. AWS credentials file is rendered

```bash
ls -l ~/.aws/credentials
head -5 ~/.aws/credentials
```

Expected: file mode `-rw-------` (`600`); header is a `[default]` (or the
first profile from `docs/catalog-b-aws-profiles.md`) section. No literal
`{{ ... }}` chezmoi markers remain.

- [ ] Pass — creds present, mode `0600`, fully rendered

### C3. AWS creds are usable

```bash
aws sts get-caller-identity --profile default 2>&1 | head -5
```

Expected: JSON output containing `UserId`, `Account`, `Arn`. Any AWS-side
error (expired token, missing account) is NOT a beget failure but does
indicate a rotation is due.

- [ ] Pass — `GetCallerIdentity` returns valid JSON

### C4. `secret_get` can fetch a known item

```bash
secret_get github-pat | head -c 4; echo '...'
```

Expected: the first 4 characters of the token, followed by `...`. Empty
output means rbw is locked or the item name is wrong.

- [ ] Pass — `secret_get` returned non-empty

---

## Section D — System

### D1. Git identity resolves correctly

```bash
# Personal context:
cd /tmp
git config --get user.email

# Analogic context (if applicable):
cd ~/sandbox/analogic 2>/dev/null && git config --get user.email
```

Expected: `/tmp` (or any non-analogic path) yields the personal email
(`brian@waveeng.com`). An analogic checkout yields `brbaker@analogic.com`
per R-24.

- [ ] Pass — both identities route per includeIf rules

### D2. User systemd units are loaded (if workstation role)

```bash
systemctl --user list-units --state=loaded --type=service | head -15
```

Expected: the units documented in Dev Spec §2 load without errors. Any
`failed` state in the output is a verification failure.

- [ ] Pass / [ ] N/A (role doesn't ship systemd units)

### D3. `chezmoi apply --dry-run` reports no pending changes

```bash
chezmoi apply --dry-run --verbose 2>&1 | tail -20
```

Expected: every line is `would be up to date` or `identical`. If any
`would be changed` / `would be created` appears after a fresh bootstrap,
the apply did not complete.

- [ ] Pass — dry-run is a no-op

### D4. Migration script is present and executable (if Phase 2 done)

```bash
ls -l scripts/migrate-secrets.sh 2>&1 || \
    ls -l ~/.local/share/chezmoi/scripts/migrate-secrets.sh
```

Expected: file present, mode has the executable bit. Only applicable after
S2.5 has landed for this machine's role.

- [ ] Pass — script present and executable

### D5. Shellcheck clean on all shipped shell code

```bash
cd ~/.local/share/chezmoi && make lint
echo "exit=$?"
```

Expected: `exit=0`, shellcheck output shows no warnings.

- [ ] Pass — `make lint` exits 0

---

## Summary

| Section | Items | Passing |
|---------|-------|---------|
| A. Shell | 4 | __/4 |
| B. Tools | 5 | __/5 |
| C. Secrets | 4 | __/4 |
| D. System | 5 | __/5 |
| **Total** | **18** | **__/18** |

**Verifier**: ______________________

**Date**: ____________________________

**Machine**: _________________________

**Role**: ____________________________

**Notes** (include failure details for any unchecked box):

___________________________________________________________________

___________________________________________________________________

---

## See Also

- `docs/runbook.md` — per-flow operational procedures.
- `docs/beget-devspec.md` — full Dev Spec (authoritative).
- `docs/catalog-a-ssh-identities.md` — SSH identity inventory.
- `docs/catalog-b-aws-profiles.md` — AWS profile inventory.
