# beget — Verification/Validation Requirements Traceability Matrix (VRTM)

This document traces every functional requirement (R-01 through R-46) in the
[Development Specification](beget-devspec.md) to the tests, flows, and manual
verifications that demonstrate compliance.

The Dev Spec declares 46 EARS-format requirements across 16 themes. Section 6
defines the test catalog (9 integration tests, 8 E2E tests, 10 manual
verifications) and the unit-test suite implemented in `tests/unit/`. This VRTM
is the bridge between requirement and evidence.

## Policy

Every R-XX row MUST reference at least one of:

- A concrete test ID (`UT` unit bats suite, `IT-NN`, `E2E-NN`, or `MV-NN`), or
- A Section 4 flow (`§4.N`), or
- A structural document artifact (checked into the repo and reviewable by
  inspection).

Rows with no verifying evidence are **blocking** — the requirement does not
ship until a test, flow, or document is added. This matrix has **zero**
untraced rows.

## Legend

| Prefix | Meaning | Location |
|---|---|---|
| `UT` | Unit tests (bats-core) | `tests/unit/*.bats` (run with `make test-unit`) |
| `IT-NN` | Integration tests | `tests/integration/*.sh`, Dev Spec §6.2 |
| `E2E-NN` | End-to-end containerized smoke tests | `tests/e2e/e2e-*.sh`, Dev Spec §6.3 |
| `MV-NN` | Manual verification procedure | Dev Spec §6 MV table; detailed steps in [`manual-verification.md`](manual-verification.md) |
| `§4.N` | Operational flow in Dev Spec Section 4 | `docs/beget-devspec.md#4-concept-of-operations` |

## Traceability Matrix

| Req ID | Summary | Category | Verifying Test IDs | Section 4 Flow | Notes |
|---|---|---|---|---|---|
| R-01 | `curl ... \| bash` bootstrap installs prereqs (chezmoi, rbw, direnv, pinentries, git, curl) | Bootstrap | E2E-01, E2E-09, E2E-10, IT-08, MV-01, `tests/unit/direnv.bats` (BASE_PREREQS), smoke-canary-ubuntu24, smoke-canary-rocky9 | §4.2 | E2E-09 (Ubuntu) and E2E-10 (Rocky) exercise the real `curl \| bash` path end-to-end against live apt/dnf via loopback HTTP server; `tests/unit/platform.bats` (`pkg_name_pinentry_tty`) covers the Rocky vs Debian pinentry-name divergence. `scripts/ci/run-smoke-canary.sh` runs the real raw-URL one-liner daily + post-merge (non-blocking) |
| R-02 | Abort when OS is not Ubuntu 24.04+ or RHEL 9+/family | Bootstrap | IT-01, `tests/unit/os-detection.bats` (`die_if_unsupported_os`), E2E-09, E2E-10, smoke-canary-ubuntu24, smoke-canary-rocky9 | §4.2 | 5 mocked-os-release unit tests cover Rocky 10, Ubuntu 26, Fedora, CentOS, AlmaLinux; E2E-09/10 confirm the bootstrap does NOT abort on the two supported families. `scripts/ci/run-smoke-canary.sh` runs the real raw-URL one-liner daily + post-merge (non-blocking) |
| R-03 | Abort if invoked as root without `--allow-root` | Bootstrap | E2E-08, `tests/unit/install.bats` (preflight root tests) | §4.2 | Override path also covered (`--allow-root` accepted) |
| R-04 | `--dry-run` prints actions without executing | Bootstrap | `tests/unit/install.bats` (parse_flags sets DRY_RUN), IT-08 | §4.2 | `chezmoi apply --dry-run` wired via `make apply-dry` |
| R-05 | `--role=<workstation\|server\|minimal>` passed to `chezmoi init --data` | Bootstrap | `tests/unit/install.bats` (parse_flags sets ROLE), E2E-01 (minimal), E2E-02 (workstation), E2E-03 (workstation/Rocky) | §4.2 | |
| R-06 | `--skip-secrets` completes bootstrap without rbw sync | Bootstrap | E2E-01, MV-06, `tests/unit/install.bats` (parse_flags sets SKIP_SECRETS) | §4.7 | Fresh-offline path |
| R-07 | Re-running `install.sh` converges to same state | Idempotency | E2E-05, IT-01 (shellcheck hygiene), IT-08 | §4.3 | |
| R-08 | `chezmoi apply` on unchanged content runs no scripts and modifies no files | Idempotency | E2E-05, E2E-06 | §4.3 | |
| R-09 | No plaintext secret values committed to the repo | Secrets/Hygiene | IT-03 (template render), `tests/unit/migrate-secrets.bats`, `tests/unit/gitconfig.bats` (no-credentials asserts) | — | Verified by grep-for-secret patterns in IT-03 render output |
| R-10 | Templates reference secrets by rbw item name, never value | Secrets/Hygiene | IT-03 | — | Enforced by `chezmoi execute-template` render in CI |
| R-11 | `~/.secrets/` directory permissions enforced to 0700 | Secrets/Hygiene | IT-03, E2E-04 | — | `private_` chezmoi prefix ensures 0700 |
| R-12 | Files within `~/.secrets/` enforced to 0600 | Secrets/Hygiene | IT-03, E2E-04 | — | `private_` chezmoi prefix ensures 0600 |
| R-13 | `secret VAR` populates `$VAR` via `rbw get <derived-item-name>` | Secrets/Env | IT-04 (`tests/unit/secret.bats`), MV-01 | §4.2 | `tests/unit/wrappers.bats` exercises gh/glab/bao tool wrappers |
| R-14 | `secret_get VAR` prints value to stdout without exporting | Secrets/Env | IT-05 (`tests/unit/secret.bats`) | §4.6 | |
| R-15 | Default rbw item derived by lowercasing + underscores→dashes | Secrets/Env | IT-06 (`tests/unit/secret.bats`) | — | e.g. `GITHUB_PAT` → `github-pat` |
| R-16 | First-use wrappers materialize `GITHUB_PAT`/`GITLAB_TOKEN`/`BAO_TOKEN` before dispatch | Secrets/Env | `tests/unit/wrappers.bats`, MV-01 | §4.2 | |
| R-17 | SSH private keys in Catalog A → `~/.ssh/` 0600 via `chezmoi apply` | Secrets/Files | IT-03, E2E-04, E2E-11, MV-08 | §4.2 | Catalog A: `docs/catalog-a-ssh-identities.md`; E2E-11 asserts 0600 mode and rbw-sourced content for every catalog-A identity after a real `chezmoi apply` into a scratch HOME |
| R-18 | `~/.aws/credentials` rendered from rbw items `aws-<profile>` with 0600 | Secrets/Files | IT-03, E2E-04, E2E-11, manual `aws sts get-caller-identity` | §4.2 | Catalog B: `docs/catalog-b-aws-profiles.md`; E2E-11 asserts 0600 mode, every `[profile]` section present, and AKIA marker count ≥ profile count after a real `chezmoi apply` |
| R-19 | VW update → `chezmoi apply` re-materializes dependent files | Secrets/Files | E2E-06, MV-02 | §4.4 | Template render output is content-derived |
| R-20 | On desktops with Secret Service, rbw uses `pinentry-gnome3` | rbw Lifecycle | MV-08 | §4.2 | Detected via `DBUS_SESSION_BUS_ADDRESS` + `XDG_CURRENT_DESKTOP` |
| R-21 | On headless sessions, rbw falls back to `pinentry-curses` | rbw Lifecycle | MV (headless-malory procedure, part of MV-08 addendum) | §4.2 | |
| R-22 | Cache serves `rbw get` when Vaultwarden is unreachable | rbw Lifecycle | MV-05 | §4.7 | |
| R-23 | Cache empty AND VW unreachable → `chezmoi apply` fails with clear message | rbw Lifecycle | E2E-07 | §4.7 | |
| R-24 | Analogic repos (`gitlab.com:analogicdev/**`) resolve to Analogic identity | Identity | MV-09, `tests/unit/gitconfig.bats` (`includeIf for analogicdev`, `~/.gitconfig-analogic` override) | §4.6 | |
| R-25 | Other repos resolve to default personal identity | Identity | MV-09, `tests/unit/gitconfig.bats` (personal user.email) | — | |
| R-26 | git `credential.helper libsecret` configured | Identity | `tests/unit/gitconfig.bats` (parseable as git config), manual verify on first push | — | |
| R-27 | `cd` into authorized `.envrc` dir → direnv loads env vars | Activity Context | MV-04, `tests/unit/direnv.bats` (hook eval present) | §4.6 | |
| R-28 | `cd` out of such a dir → direnv unloads those vars | Activity Context | `tests/unit/direnv.bats` (no `[whitelist]` auto-approval) | §4.6 | Unload is a direnv primitive; covered by direnv itself + our `.envrc` shape |
| R-29 | `.envrc` can use `export VAR=$(secret_get ctx-name)` | Activity Context | MV-04, `tests/unit/direnv.bats` (.envrc example uses secret_get) | §4.6 | |
| R-30 | Role tag controls include/exclude via tag-scoped filenames | Machine Roles | E2E-01, E2E-02, E2E-03, MV-07 | §4.2 | Prefer tag-scoped filenames over `.chezmoiignore` over inline `{{ if }}` |
| R-31 | System-state scripts escalate via explicit `sudo` | System Config | IT-01 (shellcheck + grep for `sudo`), `tests/unit/apt-repos.bats`, `tests/unit/sysctl.bats` | — | Error discipline enforced by run_onchange headers (R-44) |
| R-32 | User systemd units: `systemctl --user daemon-reload` + enable | System Config | `tests/unit/systemd.bats` (user script: daemon-reload runs once, enables timers), IT-01, `systemctl --user list-unit-files` | — | Catalog E units covered |
| R-33 | System systemd units: `sudo systemctl daemon-reload` + enable | System Config | `tests/unit/systemd.bats` (sys script: daemon-reload, enables workstation units), IT-01, E2E-02 | — | Catalog H units |
| R-34 | APT source GPG key verified before source takes effect | System Config | `tests/unit/apt-repos.bats` (signed-by= keyring, 404 aborts repo), IT-01, E2E-02 | — | Keyring 0644 perms asserted |
| R-35 | Sysctl entries installed to `/etc/sysctl.d/` + `sysctl --system` | System Config | `tests/unit/sysctl.bats` (copy + reload), IT-01, manual sysctl query | — | `vm.max_map_count`, `kernel.unprivileged_userns_clone` covered |
| R-36 | `.chezmoiexternal.toml` clones upstream projects to target paths | Upstream | `tests/unit/upstream.bats` (5 project sections, git-repo type), MV-10, IT-01 | §4.3 | refreshPeriod=168h asserted |
| R-37 | Invoke upstream-provided installer rather than hand-rolling | Upstream | `tests/unit/upstream.bats` (executes install.sh when present, logs & continues when absent), IT-01 | §4.3 | |
| R-38 | `~/.local/bin/` scripts materialize with 0755 perms | Scripts | IT-01 per script, E2E-04 (binary `--version` works), `tests/unit/tooling.bats` | §4.2 | `executable_` chezmoi prefix |
| R-39 | `$HOME/.local/bin` appears in `$PATH` ahead of `/usr/bin` / `/usr/local/bin` | Scripts | `tests/unit/tooling.bats`, MV-01 (shell ordering check) | §4.2 | |
| R-40 | All apt packages installed via single `apt-get install -y` | Packages | `tests/unit/apt-packages.bats` (common list ≥20 non-comment entries, single invocation), IT-01 | §4.2 | |
| R-41 | Role-scoped apt packages installed only when role active | Packages | `tests/unit/apt-packages.bats` (role=minimal ONLY minimal, role=workstation common+workstation), IT-01 | §4.2 | |
| R-42 | Every non-apt binary has a `run_onchange` install script | Non-apt Tools | IT-01 per script, E2E-04 (binary `--version`) | §4.2 | Each script documents source + install mechanism (R-44) |
| R-43 | `install.sh` emits intent-level log output | Observability | `tests/unit/install.bats` (usage, flag summary), MV-01 (eyeball output) | §4.2 | |
| R-44 | Every `run_onchange_*` has 3–10 line header comment (purpose, state change, preconditions) | Observability | IT-09 (`tests/integration/header-comments.sh`) | — | Mechanical check |
| R-45 | `README.md` contains disclaimer, install one-liner, Dev Spec link, supported platforms, prerequisites | Documentation | Inspection; final /dod verification | — | README sections: Status (disclaimer + Dev Spec link), One-liner install, Prerequisites, Supported Platforms |
| R-46 | `CHANGELOG.md` logs user-visible behavior changes | Documentation | Inspection; final /dod verification | — | Lives at repo root |

## Coverage Summary

**By verification category**:

- Unit tests (bats): cover R-02, R-03, R-04, R-05, R-06, R-13, R-14, R-15, R-16, R-24, R-25, R-26, R-27, R-28, R-29, R-31, R-32, R-33, R-34, R-35, R-36, R-37, R-38, R-39, R-40, R-41, R-43
- Integration tests: cover R-01, R-07, R-09, R-10, R-11, R-12, R-17, R-18, R-31, R-32, R-33, R-34, R-35, R-36, R-37, R-38, R-40, R-41, R-42, R-44
- E2E tests: cover R-01, R-02, R-03, R-05, R-06, R-07, R-08, R-11, R-12, R-17, R-18, R-19, R-23, R-30, R-33, R-38, R-42
- Manual verifications: cover R-01, R-13, R-16, R-19, R-20, R-21, R-22, R-24, R-25, R-27, R-29, R-30, R-36, R-39, R-43
- Section 4 flows: every theme with user-visible behavior maps to §4.2–§4.7
- Structural inspection only: R-45 (README contents) and R-46 (CHANGELOG presence) — reviewed at /dod

**Untraced requirements**: 0.

## How to Use This Matrix

- **When adding a requirement**: append a row with a verifying test ID, or
  explicitly update the row for an existing requirement whose scope grew.
- **When removing a test**: confirm the R-XX rows it supported still have at
  least one other verification; if not, add a replacement or mark the
  requirement for revision.
- **At /dod**: the matrix is the mechanical checklist. Every row must have a
  verifying artifact that actually runs green in CI (for automated rows) or
  has a recent PASS record in an MV runbook (for manual rows).

## See Also

- [Development Specification](beget-devspec.md) — source of R-01..R-46 and
  the IT/E2E/MV catalog (Section 6).
- [Manual Verification Procedures](manual-verification.md) — step-by-step
  for MV-01..MV-10 (created by Story S3.14).
- [Runbook](runbook.md) — day-to-day operational procedures.
- [Deployment Verification](deployment-verification.md) — post-deploy smoke
  checklist.
