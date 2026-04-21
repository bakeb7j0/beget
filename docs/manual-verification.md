# beget — Manual Verification Procedures

Ten manual verification procedures (MV-01 through MV-10), one per test in
the Dev Spec Section 6.4 table. Each MV proves that a user-visible flow
works on a real machine and cannot be automated cheaply — either because
it requires a desktop environment, a secrets vault, a distinct network
topology, or a human eyeball on UX output.

Every procedure is designed to be **paste-able into an issue**: copy the
`### MV-NN` block, paste it, and check boxes as you go. Numbered steps
use markdown checkboxes so progress is visible in GitHub's rendered view.

## Conventions

- **Preconditions** — must all hold before the first step.
- **Steps** — copy-pasteable commands in `bash` code blocks. Each numbered
  step is a single logical action, typically one command invocation.
- **Expected output** — what "success" looks like for that step; an abridged
  line or a unique marker.
- **PASS/FAIL criteria** — objective conditions at the end of the
  procedure. An MV is **PASS** only when every criterion holds.

If any step fails, stop and capture: the failing command, full stderr,
relevant env vars (`env | grep -E '^(GITHUB|GITLAB|BAO|RBW|BEGET)_'`), and
the output of `rbw status` + `chezmoi doctor`. Paste that block into a
new issue labeled `type::bug`.

## Cross-References

- Dev Spec: [`beget-devspec.md`](beget-devspec.md) — R-01..R-46 and flow definitions (§4.2..§4.7).
- VRTM: [`beget-vrtm.md`](beget-vrtm.md) — which MV traces which requirement.
- Runbook: [`runbook.md`](runbook.md) — the day-to-day step-by-step that
  MVs exercise. Pair an MV with the matching runbook section when
  preparing to run.

---

### MV-01 — First-time bootstrap on a fresh VM

**Traces**: R-01, R-16. **Flow**: §4.2. **Runbook**: §1.
**Automated coverage**: [E2E-09](../tests/e2e/e2e-09-oneliner-ubuntu.sh) exercises
the same `curl … | bash` path on Ubuntu 24.04 end-to-end against live apt (serves
install.sh over a loopback HTTP server to sidestep main-branch dependence). MV-01
remains the canonical check for the desktop/GUI and real-Vaultwarden legs that
E2E-09 deliberately skips (`--skip-secrets`, headless).

**Preconditions**
- Fresh VM (Ubuntu 24.04 or Rocky 9) with network and a non-root user.
- Vaultwarden master password known.
- `GITHUB_PAT` already exists as a Login item in Vaultwarden.

**Steps**

- [ ] 1. SSH into the VM as the non-root user.
- [ ] 2. Run the bootstrap:
  ```bash
  curl -fsSL https://github.com/bakeb7j0/beget/raw/HEAD/install.sh | bash -s -- --role=workstation
  ```
- [ ] 3. When prompted, run `rbw login` and enter the VW master password.
- [ ] 4. Wait for `chezmoi apply` to complete (5–15 minutes).
- [ ] 5. Open a new shell and confirm `~/.local/bin` is on `PATH`:
  ```bash
  echo "$PATH" | tr ':' '\n' | grep -n '.local/bin'
  ```
- [ ] 6. Exercise the gh wrapper (first-call `GITHUB_PAT` materialization):
  ```bash
  gh pr list --repo bakeb7j0/beget
  ```

**Expected output**
- Step 2: installer completes with `[install] done.`
- Step 5: a line showing `.local/bin` ahead of `/usr/bin` and `/usr/local/bin`.
- Step 6: a non-error listing of PRs (may be empty, but must not be auth-denied).

**PASS/FAIL**
- PASS: all six steps succeed, `gh pr list` returned without auth error.
- FAIL: installer aborts, `rbw login` rejects master password, or `gh`
  returns `HTTP 401`.

---

### MV-02 — Secret rotation picks up via `rbw sync`

**Traces**: R-19. **Flow**: §4.4. **Runbook**: §3.

**Preconditions**
- MV-01 passed on this machine.
- A known secret (e.g. `github-pat`) to rotate.

**Steps**

- [ ] 1. Note the current value in a scratchpad (for after-comparison):
  ```bash
  secret_get github-pat | head -c 10; echo
  ```
- [ ] 2. In the Vaultwarden UI, update the `github-pat` item to a new value and save.
- [ ] 3. Back on the machine, sync rbw's cache:
  ```bash
  rbw sync
  ```
- [ ] 4. Open a new shell (to clear the cached `$GITHUB_PAT`):
  ```bash
  bash -l
  ```
- [ ] 5. Retrieve the secret and confirm the new value:
  ```bash
  secret_get github-pat | head -c 10; echo
  ```

**Expected output**
- Step 1: first 10 chars of the old value.
- Step 5: first 10 chars of the new value (different from step 1).

**PASS/FAIL**
- PASS: step 5's head differs from step 1's head; `gh pr list` still works.
- FAIL: step 5 prints the old value, or `rbw sync` errors.

---

### MV-03 — `newsecret` end-to-end flow

**Traces**: R-13 via DM-14. **Flow**: §4.5. **Runbook**: §4.

**Preconditions**
- MV-01 passed.
- You have a fresh secret value (e.g. a throwaway test token) ready to paste.

**Steps**

- [ ] 1. Pick a unique, test-scoped name (so we can remove it after):
  ```bash
  NAME=test-mv03-$(date +%s)
  echo "$NAME"
  ```
- [ ] 2. Run `newsecret`:
  ```bash
  newsecret "$NAME"
  ```
- [ ] 3. At the prompt, paste a non-empty test value and press Ctrl-D.
- [ ] 4. Observe the helper reports the derived env-var name (e.g. `TEST_MV03_<ts>`).
- [ ] 5. Retrieve it:
  ```bash
  secret_get "$NAME"
  ```
- [ ] 6. Clean up in Vaultwarden: delete the `test-mv03-*` item.
- [ ] 7. Confirm gone: `secret_get "$NAME"` should fail with a clear "not found" error after `rbw sync`.

**Expected output**
- Step 4: a line like `env var: TEST_MV03_1700000000 (use: secret TEST_MV03_1700000000 or $(secret_get test-mv03-...))`.
- Step 5: the pasted value on stdout.
- Step 7: non-zero exit with a `rbw: item not found` style message.

**PASS/FAIL**
- PASS: created, retrieved, deleted, confirmed gone.
- FAIL: any step errors, or step 5 prints nothing.

---

### MV-04 — Activity context switch (direnv)

**Traces**: R-27, R-29. **Flow**: §4.6. **Runbook**: §5.

**Preconditions**
- MV-01 passed.
- A context directory exists (e.g. `~/sandbox/analogic/`) with an `.envrc`
  setting `GITLAB_TOKEN=$(secret_get analogic-gitlab-token)`.
- `analogic-gitlab-token` item exists in Vaultwarden.

**Steps**

- [ ] 1. From `~`, confirm `$GITLAB_TOKEN` is unset or empty:
  ```bash
  cd ~ && echo "before: ${GITLAB_TOKEN:-<unset>}"
  ```
- [ ] 2. Enter the context directory:
  ```bash
  cd ~/sandbox/analogic
  ```
- [ ] 3. If direnv warns about authorization, authorize it:
  ```bash
  direnv allow
  ```
- [ ] 4. Confirm the token is now set:
  ```bash
  echo "in-context: ${GITLAB_TOKEN:0:6}..."
  ```
- [ ] 5. Exit the directory:
  ```bash
  cd ~
  ```
- [ ] 6. Confirm the token is unset again:
  ```bash
  echo "after: ${GITLAB_TOKEN:-<unset>}"
  ```

**Expected output**
- Step 1: `before: <unset>` (or empty).
- Step 4: `in-context: abc123...` — a 6-character token prefix.
- Step 6: `after: <unset>`.

**PASS/FAIL**
- PASS: token present only while CWD is inside the context dir.
- FAIL: token persists after `cd ~`, or never appears.

---

### MV-05 — Offline mode served from rbw cache

**Traces**: R-22. **Flow**: §4.7. **Runbook**: §6.

**Preconditions**
- MV-01 passed recently (cache is populated).
- Ability to turn networking off (e.g. `nmcli networking off`, or unplug).

**Steps**

- [ ] 1. Confirm online `rbw get` works:
  ```bash
  rbw get github-pat >/dev/null && echo "online: OK"
  ```
- [ ] 2. Disable networking:
  ```bash
  sudo nmcli networking off
  ```
- [ ] 3. Confirm offline by pinging github.com (should fail):
  ```bash
  curl -sS --max-time 3 https://github.com >/dev/null && echo "still online" || echo "offline: OK"
  ```
- [ ] 4. Retrieve the secret from cache:
  ```bash
  rbw get github-pat >/dev/null && echo "cache hit: OK"
  ```
- [ ] 5. Try a tool wrapper:
  ```bash
  glab --help >/dev/null && echo "glab wrapper: OK"
  ```
- [ ] 6. Restore networking:
  ```bash
  sudo nmcli networking on
  ```

**Expected output**
- Step 1: `online: OK`.
- Step 3: `offline: OK`.
- Step 4: `cache hit: OK`.
- Step 5: `glab wrapper: OK`.

**PASS/FAIL**
- PASS: `rbw get` serves from cache while offline; wrappers still function.
- FAIL: `rbw get` errors with `Vaultwarden unreachable` while offline.

---

### MV-06 — `--skip-secrets` fresh-offline bootstrap

**Traces**: R-06. **Flow**: §4.7. **Runbook**: §1, §6.

**Preconditions**
- A fresh VM (no prior beget bootstrap).
- Vaultwarden is intentionally unreachable (blocked or off).

**Steps**

- [ ] 1. On the fresh VM, confirm VW is unreachable:
  ```bash
  curl -sS --max-time 3 https://vault.<your-domain>/ >/dev/null && echo "reachable" || echo "unreachable: OK"
  ```
- [ ] 2. Run the installer with `--skip-secrets`:
  ```bash
  curl -fsSL https://github.com/bakeb7j0/beget/raw/HEAD/install.sh | bash -s -- --role=workstation --skip-secrets
  ```
- [ ] 3. Confirm install completed:
  ```bash
  echo "$?" && test -x ~/.local/bin/newsecret && echo "newsecret present: OK"
  ```
- [ ] 4. Confirm `~/.ssh/` and `~/.aws/credentials` were NOT created:
  ```bash
  ls -la ~/.ssh/ ~/.aws/ 2>&1 | grep -E '(credentials|id_)' && echo "leaked secrets!" || echo "no secret files: OK"
  ```

**Expected output**
- Step 1: `unreachable: OK`.
- Step 2: installer completes with `[install] done.` (possibly after a "skipping secret materialization" notice).
- Step 3: `newsecret present: OK`.
- Step 4: `no secret files: OK`.

**PASS/FAIL**
- PASS: bootstrap completes; no secret files created; dotfiles/scripts in place.
- FAIL: installer aborts because it tried to reach VW, or secret files materialize anyway.

---

### MV-07 — Role change via re-init

**Traces**: R-30. **Flow**: §4.2 (init phase). **Runbook**: §9.

**Preconditions**
- MV-01 passed with `--role=workstation`.
- Ability to wipe `~/.local/share/chezmoi/` state (bootstrap is destructive for role).

**Steps**

- [ ] 1. Snapshot what's currently installed (workstation-tagged files):
  ```bash
  ls ~/.config/*workstation* ~/.local/bin/ 2>&1 | wc -l
  ```
- [ ] 2. Re-init chezmoi with the minimal role:
  ```bash
  chezmoi init https://github.com/bakeb7j0/beget --data 'role=minimal' --force
  ```
- [ ] 3. Apply:
  ```bash
  chezmoi apply --verbose
  ```
- [ ] 4. Compare: confirm workstation-scoped content was removed or masked:
  ```bash
  ls ~/.config/*workstation* 2>&1 | grep -c 'No such' || echo "workstation files remain — FAIL"
  ```

**Expected output**
- Step 3: `apply` completes; lines show workstation files being removed.
- Step 4: positive count or fail marker.

**PASS/FAIL**
- PASS: workstation-tagged files absent after role=minimal re-init; minimal-only content present.
- FAIL: workstation content persists, or init errors.

---

### MV-08 — Keyring unlock via `pinentry-gnome3`

**Traces**: R-20 (and R-21 headless addendum). **Flow**: §4.2. **Runbook**: §1.

**Preconditions**
- Physical desktop with GNOME Shell (not SSH, not headless).
- GDM login (active Secret Service session).
- MV-01 passed on this desktop.

**Steps**

- [ ] 1. Verify Secret Service is available:
  ```bash
  echo "${DBUS_SESSION_BUS_ADDRESS:-<missing>}"
  pgrep -a gnome-keyring-daemon | head -1 || echo "no keyring daemon — FAIL"
  ```
- [ ] 2. Lock rbw (forces a fresh unlock prompt):
  ```bash
  rbw lock
  ```
- [ ] 3. Trigger a secret fetch:
  ```bash
  rbw get github-pat >/dev/null
  ```
- [ ] 4. Observe the pinentry prompt: confirm it is a **GNOME dialog**, not a terminal prompt.
- [ ] 5. Enter the master password.
- [ ] 6. Confirm the secret fetch succeeded:
  ```bash
  echo "status: $?"
  ```

**Expected output**
- Step 4: a graphical dialog window titled something like "Bitwarden master password" appears.
- Step 6: `status: 0`.

**PASS/FAIL**
- PASS: prompt is graphical; secret fetched; no `pinentry-curses` fallback seen.
- FAIL: a terminal curses dialog appears (or no dialog at all), or fetch fails.

**Headless addendum (R-21)**: rerun over SSH without X forwarding; the
prompt MUST fall back to `pinentry-curses` in the terminal. Record a
separate PASS/FAIL for that.

---

### MV-09 — Git identity resolves by remote URL

**Traces**: R-24, R-25. **Flow**: §4.6 (identity aspect). **Runbook**: §11.

**Preconditions**
- MV-01 passed.
- Two scratch repos: one cloned from `git@gitlab.com:analogicdev/...`, one
  from a personal remote (e.g. `github.com:bakeb7j0/beget`).

**Steps**

- [ ] 1. In the personal repo:
  ```bash
  cd ~/sandbox/beget
  git config --show-origin user.email
  ```
- [ ] 2. In the analogicdev repo:
  ```bash
  cd ~/sandbox/analogic/<some-project>
  git config --show-origin user.email
  ```

**Expected output**
- Step 1: `file:~/.gitconfig    brian@waveeng.com` (or configured personal).
- Step 2: `file:~/.gitconfig-analogic    brbaker@analogic.com`.

**PASS/FAIL**
- PASS: the two directories show **different** `user.email`, sourced from
  different config files via `includeIf hasconfig:remote.*.url:`.
- FAIL: both show the same email, or either shows a file other than the
  expected one.

---

### MV-10 — Upstream project sync picks up new commits

**Traces**: R-36. **Flow**: §4.3 (ongoing sync). **Runbook**: §2.

**Preconditions**
- MV-01 passed.
- Ability to push a commit to at least one upstream project the VM clones
  (e.g. a disposable branch on `claudecode-workflow`).

**Steps**

- [ ] 1. Record the current HEAD of one upstream clone:
  ```bash
  cd ~/sandbox/claudecode-workflow && git rev-parse HEAD | tee /tmp/mv10-before
  ```
- [ ] 2. Push a new commit to the upstream repo (from a separate machine or
  workspace) on the default branch.
- [ ] 3. Back on the test VM, run the sync:
  ```bash
  cd ~ && chezmoi update
  ```
- [ ] 4. Record the new HEAD:
  ```bash
  cd ~/sandbox/claudecode-workflow && git rev-parse HEAD | tee /tmp/mv10-after
  ```
- [ ] 5. Compare:
  ```bash
  diff /tmp/mv10-before /tmp/mv10-after && echo "no change — FAIL" || echo "HEAD advanced: PASS"
  ```

**Expected output**
- Step 5: `HEAD advanced: PASS`.

**PASS/FAIL**
- PASS: after `chezmoi update`, the upstream clone's HEAD moved to the new commit.
- FAIL: HEAD unchanged, or `chezmoi update` errors.

---

## Recording Results

When running a full MV pass (e.g. before a release or after a major bump):

1. Open a tracking issue titled `MV pass on <host> (<date>)`.
2. For each MV you run, paste the `### MV-NN` block into a comment, check
   the boxes as you go, and capture any deviations.
3. Close the issue only when all in-scope MVs are PASS (or FAIL with a
   linked bug issue).

The goal is a machine-and-date-stamped record of manual verification,
suitable for audit alongside the automated test artifacts in
`tests/results/`.
