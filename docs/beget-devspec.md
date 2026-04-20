<!-- DEV-SPEC-APPROVAL
approved: true
approved_by: BJ Baker
approved_at: 2026-04-20T18:17:38-04:00
finalization_score: 7/7
-->

# beget — Development Specification

**Status**: Approved 2026-04-20
**Date**: 2026-04-20
**Owner**: BJ Baker
**Repository**: `bakeb7j0/beget` (GitHub, public)

---

## 1. Problem Domain

### 1.1 Background

BJ's primary workstation (malory) is a heavily customized Ubuntu 24.04 machine accumulated over years: 144 manually-installed apt packages beyond the installer baseline, ~25 hand-written scripts in `~/.local/bin/`, 5 user GNOME extensions, 5 user systemd units, custom `~/.colortintrc` visual-identity system driving Ghostty, custom tmux configuration with popup bindings and quick-SSH shortcuts, 4+ SSH identities across personal and client work, a collection of 80+ secrets historically stored as plaintext files in `~/secrets/`, per-context git identity needs (Analogic `brbaker@analogic.com` vs. personal `brian@waveeng.com`), and AWS CLI profiles for multiple accounts.

All of this has been hand-rolled and lives on one machine. Replicating the environment to a new machine (replacement workstation, laptop, VM, server) is currently a manual reconstruction from memory — prone to gaps, tool-version drift, and silent loss of customization. Secrets management has been deferred to plaintext files in `~/secrets/`, which were discovered to be group-readable (`0664`) until recently hardened.

### 1.2 Problem Statement

BJ needs a reproducible, one-command bootstrap process for a new Linux machine that:

1. Installs the canonical set of packages and third-party tools
2. Applies all dotfile configurations (shell, terminal, tmux, git, ssh, editor)
3. Materializes file-shaped secrets (SSH keys, AWS credentials) from a secure source
4. Configures env-var secrets for lazy materialization (no plaintext on disk, no eager export)
5. Sets up per-context identity (git user, GITLAB_TOKEN) that works across projects
6. Handles both Ubuntu and RHEL-family distributions
7. Supports variance across machine roles (workstation, server, minimal)
8. Works offline after initial sync (no hard dependency on homelab being reachable for daily use)
9. Installs custom user systemd units and system-level configuration (sysctl, apt repos)
10. Bootstraps upstream personal tools (claudecode-workflow, tuneviz, gitlab-settings-automation, release-mgr, claude-code-switch)

### 1.3 Proposed Solution

A public GitHub repository `bakeb7j0/beget` that encodes **BJ's specific Linux working environment** and is itself a chezmoi source repo. It is not a generic tool — it is a serialized description of one developer's workstation setup, tool choices, shell idioms, and configuration preferences, packaged as a reproducible bootstrap. The one-liner:

```bash
curl -fsSL https://github.com/bakeb7j0/beget/raw/HEAD/install.sh | bash
```

…is equivalent to "make this machine look like BJ's other machines." Forking it and swapping the secret references, git identity, and cosmetic preferences is viable; using it as-is on someone else's machine is not the intent.

install.sh installs prerequisites (chezmoi, rbw, pinentry-gnome3, pinentry-curses, direnv, git, curl), runs `chezmoi init` against the beget repo itself, and then `chezmoi apply`. All remaining concerns live as chezmoi-managed content in the same repo: templates, `run_onchange_*` scripts, private-prefixed key files, executable scripts, and the `dot_*` dotfile tree.

**Secrets** are stored in the existing homelab Vaultwarden instance and accessed via `rbw`. File-shaped secrets (SSH keys, AWS credentials) are materialized by chezmoi templates at apply time. Env-var secrets (PATs, API keys) are lazily materialized by per-tool shell wrappers (`gh`, `glab`, `bao`) and on-demand helper functions (`secret`, `secret_get`). rbw's encrypted local cache handles offline operation after initial sync.

**Git identity** per-context uses git's native `[includeIf "hasconfig:remote.*.url:..."]`. **Activity context** (which `GITLAB_TOKEN` resolves in a given repo) uses **direnv** per-directory `.envrc` files as the primary mechanism.

**Machine roles** (workstation, server, minimal) are expressed as chezmoi tags, with role-specific files and directories using chezmoi's tag-scoped filename convention rather than inline template conditionals.

The install.sh is a **stable public API**: underlying tooling (chezmoi today, potentially something else tomorrow) can change without breaking the one-liner.

### 1.4 Target Users

**Primary user: BJ** — and only BJ as a day-to-day user. The project replicates BJ's personal development environment across all his present and future Linux machines (workstations, laptops, homelab servers). Every design decision optimizes for BJ's workflow, BJ's tool preferences, BJ's context-switching patterns (personal vs. client work). There is no anticipated second operator.

**Secondary**: Developers in BJ's network, or adjacent practitioners encountering the repo publicly, who may find patterns worth adapting — fork the repo, strip the BJ-specific references, and use as a starting scaffold. This is an incidental benefit, not a design goal. External PRs are not merged; external issues are permitted but not solicited.

### 1.5 Non-Goals

This project is explicitly NOT:

1. **A secret store** — secret VALUES live in Vaultwarden. This repo contains only references to secrets by name. Nothing sensitive is ever committed.
2. **A general-purpose dev environment provisioner** — this encodes BJ's setup specifically.
3. **A multi-user fleet management tool** — no Ansible/Salt/Puppet intent.
4. **A container orchestrator or provisioner**.
5. **A package manager replacement** — orchestrates apt/dnf, doesn't replace them.
6. **A macOS, Windows, or BSD bootstrap** — Linux only (Ubuntu and RHEL-family).
7. **A CI-environment bootstrap** — a `minimal` profile exists but is not the primary focus.
8. **A project-data replicator** — does NOT copy host-specific data (project repos, downloads, media).
9. **A recovery tool for lost Vaultwarden master passwords** — relies on upstream VW recovery.
10. **A first-time-bootstrap without network** — initial clone + rbw sync requires network; ongoing use works offline.
11. **A replacement for FreeIPA/SSSD** — centralized authorized_keys stays with FreeIPA; beget handles client-side private keys and SSH config only.
12. **A collaboration or contribution platform** — no external PRs merged; forks are users' own responsibility.

---

## 2. Constraints

### 2.1 Technical Constraints

**Platform & environment**:

1. **Linux only**, specifically **Ubuntu 24.04 LTS+** and **RHEL 9+** (including RHEL-family: Fedora current stable, Rocky Linux 9+, AlmaLinux 9+). No macOS, Windows, or BSD support.
2. **Bash is the target shell.** All scripts, helpers, and wrappers assume bash (not POSIX sh, not zsh).
3. **Must support both GNOME-on-Xorg and headless** — GNOME-specific functionality is tag-gated to the `workstation` role.

**Bootstrap prerequisites**:

4. **Install via `curl | bash`** with no prerequisites beyond `curl`, `bash`, and network.
5. **Idempotent** — re-running install.sh on an already-bootstrapped machine must be safe.
6. **Network required for first-time bootstrap**; subsequent operations (via chezmoi apply and rbw cache) must work offline.

**External services**:

7. **Vaultwarden at existing homelab URL** — reachable at install time; temporary unavailability handled via rbw's encrypted local cache.
8. **GitHub public repo** — beget itself must be reachable at `github.com/bakeb7j0/beget`. No mirror.

**Content & tooling**:

9. **chezmoi is the primary content manager.** Beget's repo layout follows chezmoi's conventions.
10. **rbw (not bw) for secret access** — rbw has an encrypted local cache enabling offline use.
11. **git ≥ 2.36** required for `includeIf "hasconfig:remote.*.url:..."` matcher.
12. **Secret Service API** (DBus) required for keyring-backed rbw on desktop; `pinentry-curses` is the headless fallback.
13. **Root privilege escalation via sudo** — individual run_onchange scripts that need root invoke `sudo` explicitly.

**Security & permissions**:

14. **Zero plaintext secrets in git-tracked content**.
15. **File permissions strictly enforced**: 0700 on `~/.secrets/` dir, 0600 on files within; 0600 on `~/.ssh/id_*`; 0600 on `~/.aws/credentials`.
16. **No credentials cached in process environment at shell start** — env-var secrets materialize on-demand.

### 2.2 Product Constraints

**Ownership & governance**:

1. **Public repository**, **solo-maintained by BJ**. Social contract is "look but don't touch."
2. **No external PRs merged.** Forks welcomed; contributions back not accepted.
3. **Issues remain open** for BJ's own change-tracking workflow (`/ibm`).

**Content policy**:

4. **Nothing sensitive committed** to the repo. Enforced by design, review discipline, and `.gitignore`.
5. **No hostnames of internal homelab services** in grep-able comments.

**Release & versioning**:

6. **Versioning via git tags**; no formal release cadence.
7. **install.sh URL is a stable public API.**

**Documentation**:

8. **Runs and scripts carry intent-level comments** — explains why each run_onchange script exists and what it changes.
9. **README.md** contains the disclaimer, one-liner, and pointer to the Dev Spec.

**Compatibility & stability**:

10. **No backward-compatibility guarantees** for intermediate states.

---

## 3. Requirements (EARS)

### Theme 1 — Bootstrap and Installation

**R-01** — When the user invokes `curl -fsSL https://github.com/bakeb7j0/beget/raw/HEAD/install.sh | bash`, the system shall install chezmoi, rbw, direnv, pinentry-gnome3, pinentry-curses, git, and curl.

**R-02** — When install.sh detects an unsupported OS (not Ubuntu 24.04+ or RHEL 9+/family), the system shall abort with a clear error.

**R-03** — When install.sh is invoked as root without `--allow-root`, the system shall abort.

**R-04** — When `--dry-run` is set, install.sh shall print actions without executing them.

**R-05** — When `--role=<workstation|server|minimal>` is set, install.sh shall pass the role tag to `chezmoi init --data`.

**R-06** — When `--skip-secrets` is set, install.sh shall complete bootstrap without rbw sync or secret materialization.

### Theme 2 — Idempotency

**R-07** — Re-running install.sh shall converge to the same state without accumulation.

**R-08** — `chezmoi apply` on unchanged content shall produce no file modifications or run_onchange executions.

### Theme 3 — Secrets: Storage and Hygiene

**R-09** — The system shall not commit plaintext secret values to the repository.

**R-10** — Templates shall reference secrets by rbw item name, never by value.

**R-11** — `chezmoi apply` shall enforce `~/.secrets/` directory permissions to 0700.

**R-12** — `chezmoi apply` shall enforce file permissions within `~/.secrets/` to 0600.

### Theme 4 — Secrets: Shell Materialization (env-var)

**R-13** — When `secret VAR` is invoked and `$VAR` is empty, the system shall populate it via `rbw get <item-name>`.

**R-14** — When `secret_get VAR` is invoked, the system shall retrieve the value from rbw and print it to stdout without exporting.

**R-15** — The system shall derive the default rbw item name from an env var name by lowercasing and converting underscores to dashes.

**R-16** — When `gh`, `glab`, or `bao` is invoked for the first time in a shell session, the system shall materialize `GITHUB_PAT`, `GITLAB_TOKEN`, or `BAO_TOKEN` respectively from rbw before dispatching.

### Theme 5 — Secrets: File Materialization (chezmoi-templated)

**R-17** — When `chezmoi apply` runs with rbw initialized, the system shall materialize SSH private keys listed in Catalog Section A to `~/.ssh/` with 0600 permissions.

**R-18** — When `chezmoi apply` runs with rbw initialized, the system shall materialize `~/.aws/credentials` from rbw items matching `aws-<profile>` (for profiles with long-lived creds) with 0600 permissions.

**R-19** — When a secret is updated in Vaultwarden and `chezmoi apply` is subsequently invoked, the system shall update dependent materialized files.

### Theme 6 — rbw Lifecycle

**R-20** — On desktops with a running Secret Service, rbw shall present password prompts via `pinentry-gnome3`.

**R-21** — On headless sessions, rbw shall fall back to `pinentry-curses`.

**R-22** — While rbw's local encrypted cache is populated and Vaultwarden is unreachable, `rbw get` shall continue to resolve from cache.

**R-23** — If rbw's local cache is empty AND Vaultwarden is unreachable, `chezmoi apply` shall fail with a clear message identifying the unavailability.

### Theme 7 — Identity

**R-24** — In repositories with remote URL matching `git@gitlab.com:analogicdev/**`, git shall resolve `user.email` to the Analogic identity via `includeIf hasconfig:remote.*.url:`.

**R-25** — In other repositories, git shall resolve `user.email` to the default personal identity.

**R-26** — The system shall configure `git credential.helper libsecret`.

### Theme 8 — Activity Context

**R-27** — When the user enters a directory with a direnv-authorized `.envrc`, the system shall load its environment variables.

**R-28** — When the user exits such a directory, the system shall unload those variables.

**R-29** — `.envrc` files shall be able to use `export VAR=$(secret_get <context>-<name>)` to scope context-specific secrets to a directory subtree.

### Theme 9 — Machine Roles

**R-30** — `chezmoi apply` shall include/exclude files based on the role tag set at `chezmoi init`, using tag-scoped filenames and directories rather than inline template conditionals in shared files.

### Theme 10 — System-Level Configuration

**R-31** — Scripts that modify system state shall escalate via `sudo` explicitly.

**R-32** — When a user systemd unit from Catalog Section E is installed, the system shall run `systemctl --user daemon-reload` and enable the unit.

**R-33** — When a system systemd unit from Catalog Section H is installed, the system shall run `sudo systemctl daemon-reload` and enable the unit (tag-scoped if host-specific).

**R-34** — When an APT source from Catalog Section H is added, the system shall verify the GPG signing key is present and valid before the source takes effect.

**R-35** — The sysctl entries from Catalog Section H shall be installed to `/etc/sysctl.d/` and applied with `sysctl --system`.

### Theme 11 — Upstream Project Integration

**R-36** — `chezmoi apply` shall clone the upstream projects (claudecode-workflow, tuneviz, gitlab-settings-automation, release-mgr, claude-code-switch) to their designated target paths via `.chezmoiexternal.toml`.

**R-37** — Where an upstream project provides a one-line installer, the system shall invoke that installer rather than hand-rolling install steps.

### Theme 12 — Custom Scripts

**R-38** — `chezmoi apply` shall materialize user scripts (disposition = migrate) to `~/.local/bin/` with 0755 permissions.

**R-39** — `$HOME/.local/bin` shall appear in `$PATH` ahead of `/usr/bin` and `/usr/local/bin`.

### Theme 13 — APT Packages

**R-40** — The system shall install all apt packages listed in the canonical package lists via a single `apt-get install -y` invocation.

**R-41** — Role-scoped apt packages shall be installed only when the corresponding role is active.

### Theme 14 — Non-apt Tooling

**R-42** — Each non-apt binary shall have a `run_onchange` install script documenting its source and install mechanism.

### Theme 15 — Observability

**R-43** — install.sh shall emit intent-level log output during execution.

**R-44** — Every `run_onchange` script shall carry a leading comment (3–10 lines) explaining its purpose, what state it changes, and any preconditions.

### Theme 16 — Documentation

**R-45** — The repository root shall contain `README.md` with: the "look but don't touch" disclaimer, the one-liner install command, a link to the Dev Spec, supported platforms, and environment prerequisites.

**R-46** — The repository shall contain `CHANGELOG.md` logging user-visible behavior changes.

---

## 4. Concept of Operations

### 4.1 System Context

beget sits between three external systems and the target machine:

```
    ┌─────────────────────┐
    │  GitHub             │
    │  (bakeb7j0/beget    │◀──── clone via
    │   public repo)      │      install.sh + chezmoi
    └─────────────────────┘             │
              │                         ▼
    ┌─────────────────────┐     ┌──────────────────┐
    │  Vaultwarden        │◀────│  Target Machine  │
    │  (homelab)          │     │  (malory / new)  │
    │  + ~/.cache/rbw/    │     │  Ubuntu or RHEL  │
    └─────────────────────┘     └──────────────────┘
              ▲                         │
              │                         ▼
              │                 ┌──────────────────┐
              │                 │  Upstream repos  │
              └── rbw get       │  (claudecode-    │
                                │   workflow,      │
                                │   tuneviz,       │
                                │   release-mgr,   │
                                │   claude-code-   │
                                │   switch, etc.)  │
                                └──────────────────┘
```

**External dependencies**: GitHub (beget repo), Vaultwarden (secrets), upstream personal-tool repos.

**Target machine outputs**: installed packages, dotfiles, rendered templates (SSH keys, AWS credentials), running systemd units, configured shell, scripts in `~/.local/bin/`, system-level config (sysctl, apt repos).

**Explicit non-participants**: FreeIPA (separate concern, server-side authorized_keys).

### 4.2 Fresh Machine Bootstrap (primary flow)

**Trigger**: BJ has a new Linux machine with minimal OS install and network.

**Preconditions**: Ubuntu 24.04+ or RHEL 9+/family. VW master password memorized. Network to github.com + Vaultwarden.

**Sequence**:

1. BJ runs `curl -fsSL https://github.com/bakeb7j0/beget/raw/HEAD/install.sh | bash -s -- --role=workstation`.
2. install.sh runs pre-flight: not-root check, network check, OS detection.
3. install.sh installs prerequisites.
4. install.sh runs `chezmoi init https://github.com/bakeb7j0/beget --data 'role=workstation'`.
5. chezmoi clones beget to `~/.local/share/chezmoi/`.
6. install.sh checks `rbw status`; prompts BJ to `rbw login` interactively.
7. install.sh runs `chezmoi apply`: run_onchange scripts execute in order, dotfiles materialize, private templates pull from rbw, scripts land in `~/.local/bin/`, upstream projects clone.
8. Completion message; BJ opens a new terminal.

**Duration**: 5–15 minutes (package downloads dominate).

**Postconditions**: Functional BJ-environment. Ongoing sync via `chezmoi apply`.

### 4.3 Ongoing Sync

**Trigger**: Updates pushed to beget repo OR secrets rotated in Vaultwarden.

**Sequence**:

1. BJ runs `chezmoi update` (= `git pull` + `chezmoi apply`).
2. chezmoi pulls latest beget commit.
3. `run_onchange_*` scripts re-run if content changed.
4. Templates re-render; updated VW secrets trigger file re-materialization.
5. Unchanged files remain untouched (idempotent).

**Duration**: Seconds to a minute.

### 4.4 Secret Rotation

**Trigger**: BJ rotates a secret.

**Sequence**:

1. BJ updates secret's value in Vaultwarden.
2. On each machine: file-shaped secrets update on next `chezmoi apply`; env-var secrets refresh on next wrapper invocation after `rbw sync`.

**Key property**: One update in VW propagates everywhere.

### 4.5 Adding a New Secret

**Trigger**: New API key / token / credential acquired.

**Sequence**:

1. BJ runs `newsecret <name>` from any shell.
2. Prompt: "Paste value (Ctrl-D when done):".
3. BJ pastes; helper creates VW Login with matching name.
4. Helper reports the derived env-var name and usage hint.
5. `secret <VAR>` or `$(secret_get <VAR>)` works immediately.

### 4.6 Activity Context Switch (direnv)

**Trigger**: BJ `cd`'s into a context-scoped directory.

**Sequence**:

1. direnv detects `.envrc` (e.g., `~/sandbox/analogic/.envrc`).
2. If not authorized, direnv prompts `direnv allow`. BJ authorizes once.
3. direnv loads env vars defined in `.envrc` (e.g., `export GITLAB_TOKEN=$(secret_get analogic-gitlab-token)`).
4. `rbw get` retrieves, populates for directory's duration.
5. `glab mr list` now shows Analogic projects.
6. `cd` out → direnv unloads.

### 4.7 Offline Operation

**Already-bootstrapped machine**: rbw cache serves `rbw get` calls; on reconnect, `rbw sync` refreshes.

**Fresh machine + offline**: install.sh with `--skip-secrets` completes bootstrap without secret materialization. Machine has basic environment. On reconnect, `rbw login && rbw sync && chezmoi apply` catches up secret-dependent content.

---

## 5. Detailed Design

### 5.1 install.sh — bootstrap entry

~100-line bash script. Structure:

```bash
#!/usr/bin/env bash
set -euo pipefail

# flag parsing: --dry-run, --role=<X>, --skip-secrets, --allow-root, --help
# pre-flight: EUID check, network check, OS detection (sources lib/platform.sh)
# prereqs: pkg_install chezmoi rbw direnv pinentry-gnome3 pinentry-curses git curl
# chezmoi init https://github.com/bakeb7j0/beget --data "role=$role"
# rbw_prompt_if_needed (unless --skip-secrets)
# chezmoi apply ${dry_run:+--dry-run}
```

**OS-detection abstraction** (`lib/platform.sh`) provides `pkg_install`, `pkg_repo_add`, `is_gnome`, `die_if_unsupported_os`.

**Error discipline**: every failure path ends with `die "<clear message>"`.

### 5.2 Chezmoi source repo layout

See sketchbook's full tree for the reference; key conventions:

- Numeric prefix on `run_onchange_before_*` scripts controls order: 00 (preflight) → 10 (apt repos) → 20 (packages) → 30 (sysctl) → 40 (systemd) → 50 (secrets perms) → 60 (git credential helper) → 70 (GNOME) → 90 (upstream, after).
- **Tag-scoped filenames**: `dirname_tagname_rest.sh` only materializes when `tagname` matches active role.
- **`private_*` prefix** → 0700 dirs, 0600 files.
- **`executable_*` prefix** → 0755.
- **`.tmpl` suffix** → chezmoi templating enabled.

### 5.3 Secrets architecture

Two subsystems:

**Subsystem A: Shell env-var secrets** (lazy materialization)
- `dot_bashrc.d/executable_50-wrappers.sh` defines `secret()`, `secret_get()`, tool wrappers
- Naming convention: `GITHUB_PAT` ↔ `github-pat`
- Context-prefix escape: `secret VAR context-name`

**Subsystem B: File-shaped secrets** (chezmoi-templated, eager at apply)
- Templates under `private_dot_ssh/`, `private_dot_aws/`
- Invoke rbw at apply time via chezmoi template functions
- Permissions from `private_` prefix

**Error handling**:
- `secret()` on missing item: stderr warning, `$VAR` empty, `return 1`
- Template missing rbw item: chezmoi apply aborts with line reference

### 5.4 Identity and activity context

**Git identity**: `~/.gitconfig` template with `[includeIf "hasconfig:remote.*.url:git@gitlab.com:analogicdev/**"] path = ~/.gitconfig-analogic`. `~/.gitconfig-analogic` overrides `user.email = brbaker@analogic.com`.

**Activity context**: direnv per-directory `.envrc` files. Example:
```bash
# ~/sandbox/analogic/.envrc
export BEGET_CONTEXT=analogic
export GITLAB_TOKEN=$(secret_get analogic-gitlab-token)
```
direnv's `allow` step is intentional friction for security.

### 5.5 Machine roles

Three values: `workstation`, `server`, `minimal`. Set at `chezmoi init` via `--data 'role=X'`.

Discipline: prefer tag-scoped filenames over `.chezmoiignore` logic over inline `{{ if }}` — in that order.

### 5.6 System-level configuration

All state-modifying work in `run_onchange_before_*` scripts with `sudo`. Standard header:

```bash
#!/usr/bin/env bash
# Purpose: <what this script does>
# Idempotency: <how it detects no-op>
# Requires: <sudo, curl, etc.>
# Tag: <if role-scoped>
set -euo pipefail
```

Subsystems: apt repos (10), packages (20), sysctl (30), systemd user (40), systemd system (41), secrets perms (50), git credential helper (60), GNOME keybindings (70-workstation).

### 5.7 Package and tooling installation

**APT packages**: `share/apt-packages-{common,workstation,server,minimal}.list`. Installed by role-scoped run_onchange.

**Non-apt tooling**: Per-category run_onchange scripts (download-binary, shell-installer, pipx, tarball). Each declares source, version, checksum.

### 5.8 Upstream project integration

`.chezmoiexternal.toml` entries for: claudecode-workflow, tuneviz, gitlab-settings-automation, release-mgr (GitLab: analogicdev/internal/tools/release-mgr), claude-code-switch (GitLab: analogicdev/internal/tools/claude-code-switch). 168h refresh period.

`run_onchange_after_90-upstream-install.sh` invokes each project's `install.sh` if present.

### 5.9 Helper scripts

**`secret` / `secret_get`** — in `dot_bashrc.d/executable_50-wrappers.sh`.

**Tool wrappers**:
```bash
gh()   { secret GITHUB_PAT   || return 1; command gh   "$@"; }
glab() { secret GITLAB_TOKEN || return 1; command glab "$@"; }
bao()  { secret BAO_TOKEN    || return 1; command bao  "$@"; }
```

**`newsecret`** — installed to `~/.local/bin/newsecret`. Argument: name. Prompts stdin paste. Rejects duplicates. Creates VW Login item.

---

### 5.A Deliverables Manifest

| ID | Deliverable | Category | File Path | Produced In |
|---|---|---|---|---|
| DM-01 | README.md (includes env prerequisites) | Docs | `README.md` | Phase 1 |
| DM-02 | Makefile (lint, apply-dry, apply, verify, test) — used locally AND in CI | Code | `Makefile` | Phase 1 |
| DM-03 | CI/CD pipeline (invokes `make` targets) | Code | `.github/workflows/ci.yml` | Phase 3 |
| DM-04 | Automated test suite (shellcheck, template render, unit, smoke) | Test | `tests/` | Phase 3 |
| DM-05 | Test results (JUnit XML) | Test | `tests/results/` (gitignored; CI publishes as artifacts) | Phase 3 |
| DM-06 | Coverage report | Test | N/A — because coverage on bash-heavy codebases is impractical | — |
| DM-07 | CHANGELOG | Docs | `CHANGELOG.md` | Phase 1 |
| DM-08 | VRTM (requirements → tests/flows) | Trace | `docs/beget-vrtm.md` | Phase 3 |
| DM-09 | Audience-facing doc (operations runbook) | Docs | `docs/runbook.md` | Phase 2 |
| DM-10 | Architecture doc | Docs | N/A — because covered by Dev Spec Section 5 | — |
| DM-11 | Deployment verification checklist | Docs | `docs/deployment-verification.md` | Phase 2 |
| DM-12 | Environment prerequisites doc | Docs | N/A — because folded into README (DM-01) | — |
| DM-13 | `install.sh` (bootstrap entry point) | Code | `install.sh` | Phase 1 |
| DM-14 | `newsecret` helper | Code | `dot_local/bin/newsecret` | Phase 2 |
| DM-15 | Secrets migration script | Code | `scripts/migrate-secrets.sh` | Phase 2 |
| DM-16 | Manual verification procedures document | Docs | `docs/manual-verification.md` | Phase 3 |

**13 active deliverables, 3 N/A with rationale.**

### 5.B Installation & Deployment

- **Initial install**: the one-liner (Section 4.2)
- **Day-to-day sync**: `chezmoi update` (= `git pull` + `chezmoi apply`)
- **Release cadence**: none formal. BJ pushes to `main`; machines pull when BJ runs `chezmoi update`.
- **Rollback**: `git revert` + `chezmoi apply`.
- **CI**: GitHub Actions from Phase 3 (shellcheck, template render, containerized smoke).

### 5.C Open Questions

1. **`refreshPeriod` for external repos** — 168h (weekly) starting guess; tune based on usage.
2. **`newsecret` with context prefixes** — v1 accepts full name; `--context` flag may come later.
3. **Package list canonical ownership** — manual edit for v1; helper (`beget package add`) later.
4. **Auto-update mechanism** — not in v1; BJ runs manually.
5. **Role changes on existing machine** — `install.sh --reconfigure` flag; defer to Phase 3.

---

## 6. Test Plan

### 6.1 Test Strategy

Testing a machine-bootstrap project has structural challenges: CI can't spin up real laptops, side-effectful operations need real OS, user-interactive pieces resist automation.

**Five tiers of defense in depth**:
1. **Static analysis** — shellcheck, shfmt
2. **Template validation** — chezmoi execute-template
3. **Unit tests** — bats-core for bash helpers
4. **Containerized integration** — Docker (Ubuntu 24.04, Rocky 9)
5. **Manual verification** — checklist on real malory / VM

**Out of automation scope**: hardware (DisplayLink, sound), live GNOME desktop integration, real Vaultwarden round-trip.

**Tooling**: shellcheck, shfmt, bats-core, Docker.

### 6.2 Integration Tests

| ID | Test | Verifies |
|---|---|---|
| IT-01 | `shellcheck` across all `*.sh` passes | R-07, hygiene |
| IT-02 | `shfmt --diff` reports no drift | formatting |
| IT-03 | `chezmoi execute-template` on every `*.tmpl` renders without error | R-10, R-11, R-17, R-18 |
| IT-04 | bats-core tests for `secret()` | R-13 |
| IT-05 | bats-core tests for `secret_get()` | R-14 |
| IT-06 | bats-core tests for name conversion | R-15 |
| IT-07 | bats-core tests for `newsecret` | — |
| IT-08 | `make lint / apply-dry / verify / test` succeed on clean checkout | R-07, DM-02 |
| IT-09 | Every `run_onchange_*` script passes shellcheck and has required header comment | R-44 |

### 6.3 End-to-End Tests

| ID | Test | Verifies |
|---|---|---|
| E2E-01 | Fresh Ubuntu 24.04: `install.sh --role=minimal --skip-secrets` | R-01, R-06, R-30 |
| E2E-02 | Fresh Ubuntu 24.04: `install.sh --role=workstation --skip-secrets` | R-30, R-33 |
| E2E-03 | Fresh Rocky 9: `install.sh --role=workstation --skip-secrets` | R-02 |
| E2E-04 | Mock rbw cache: `install.sh` materializes SSH/AWS | R-17, R-18 |
| E2E-05 | Re-run `install.sh` on bootstrapped container | R-07, R-08 |
| E2E-06 | Modify template → `chezmoi apply` → only affected files change | R-08, R-19 |
| E2E-07 | Mock rbw missing item → `chezmoi apply` fails gracefully | R-23 |
| E2E-08 | Root-user container without `--allow-root` → exits non-zero | R-03 |

### 6.4 Manual Verification Procedures

| ID | Procedure | Verifies |
|---|---|---|
| MV-01 | First-time bootstrap on fresh VM; follow runbook; `gh pr list` succeeds | §4.2; R-01, R-16 |
| MV-02 | Secret rotation: update in VW → `rbw sync` → `gh` picks up | §4.4; R-19 |
| MV-03 | `newsecret` flow end-to-end | §4.5; DM-14 |
| MV-04 | Context switch: Analogic dir → GITLAB_TOKEN flips | §4.6; R-27, R-29 |
| MV-05 | Offline mode: disable network → `glab pr list` works via cache | §4.7; R-22 |
| MV-06 | `--skip-secrets` fresh-offline bootstrap | §4.7; R-06 |
| MV-07 | Role change: re-init with `--data role=minimal` | R-30 |
| MV-08 | Keyring unlock UX: GDM login → rbw unlocks via pinentry-gnome3 | R-20 |
| MV-09 | Git identity: analogicdev repo → Analogic email; personal repo → default | R-24, R-25 |
| MV-10 | Upstream project sync picks up new commits | R-36 |

---

## 7. Definition of Done

### 7.1 Project-level DoD

- All active manifest rows have file paths OR N/A rationale (checked by 7.2)
- All active manifest rows have "Produced In" phase (checked by 7.2)
- All Section 3 requirements trace to a test or verification (DM-08 VRTM)
- CI green on `main`
- Runbook (DM-09) describes every Section 4 flow
- README contains one-liner, disclaimer, env prerequisites, Dev Spec link
- No plaintext secrets in repo
- Self-review completed on every commit merged to `main`

### 7.2 Dev Spec Finalization Checklist

- [ ] Check 1: Tier 1 file paths — every Tier 1 row has path or N/A rationale
- [ ] Check 2: Tier 2 triggers — every fired trigger has a manifest row
- [ ] Check 3: Wave assignments — every active row has "Produced In"
- [ ] Check 4: MV-XX coverage — covered by DM-16
- [ ] Check 5: Verbs without nouns — all deliverables have file artifacts
- [ ] Check 6: Audience-facing doc — DM-09 has path
- [ ] Check 7: Unified DoD references — §7 references Deliverables Manifest (§5.A)

### 7.3 Per-phase DoD

**Phase 1 — Core bootstrap (MUST)**:
- [ ] `install.sh` (DM-13) handles all flags and pre-flight
- [ ] `README.md` (DM-01) + `CHANGELOG.md` (DM-07) drafted
- [ ] `Makefile` (DM-02) has lint/apply-dry/apply/verify targets
- [ ] `--role=minimal --skip-secrets` bootstrap succeeds on Ubuntu + Rocky (E2E-01, E2E-03)
- [ ] Chezmoi source structure in place (baseline dotfiles)
- [ ] Git identity via includeIf working (MV-09)

**Phase 2 — Secrets + operational docs (MUST)**:
- [ ] rbw wrappers + helpers (R-13–R-16)
- [ ] `newsecret` (DM-14, MV-03)
- [ ] SSH key templates (R-17, E2E-04, MV-08)
- [ ] AWS credentials template (R-18)
- [ ] Secrets migration script (DM-15)
- [ ] direnv + Analogic context (MV-04)
- [ ] Runbook (DM-09) covers §4.2–§4.7
- [ ] Deployment verification checklist (DM-11)

**Phase 3 — Full migration + CI (MUST)**:
- [ ] All apt packages installable (R-40, R-41)
- [ ] Non-apt tooling scripts (R-42)
- [ ] Upstream projects integrated (R-36)
- [ ] System-level config (R-34, R-35)
- [ ] User systemd units (R-32)
- [ ] GitHub Actions CI (DM-03)
- [ ] Test suite (DM-04) green — shellcheck + bats + template render + containerized smoke
- [ ] Test results (DM-05)
- [ ] VRTM (DM-08) populated
- [ ] Manual verification procedures doc (DM-16)

### 7.4 Per-feature DoD

- shellcheck passes on modified scripts
- bats-core tests added for new bash helpers
- Runbook (DM-09) reflects behavior changes
- CHANGELOG entry added
- If requirements touched: VRTM updated
- CI green on PR branch
- Self-review completed

---

## 8. Phased Implementation Plan

### Phase 1 — Core Bootstrap

**Phase DoD**: install.sh runs `chezmoi init && apply` on a fresh Ubuntu 24.04 or Rocky 9 VM; `--skip-secrets` bootstrap lands a usable shell with correct dotfiles and git identity. No secrets yet.

#### Wave 1.1 — Foundations (parallel)

##### Story: Repo Scaffolding

**Summary**: Initial beget repo structure with README placeholder, CHANGELOG initialized, Makefile skeleton, LICENSE, `.gitignore`.

**Implementation steps**:
1. Create `README.md` with title, one-liner placeholder, disclaimer, link to Dev Spec, env prerequisites section stub
2. Create `CHANGELOG.md` with `## [Unreleased]` section
3. Create empty `Makefile` (targets added in next story)
4. Create `.gitignore` with: `*.bak`, `.env*`, `*.key`, `*.pem`, `secrets/`, test artifacts, chezmoi state dirs
5. Add MIT LICENSE

**Test procedures**: IT-02, visual verification.

**Acceptance criteria**:
- [ ] `README.md` contains disclaimer, one-liner, Dev Spec link, env prerequisites, supported platforms
- [ ] `CHANGELOG.md` has valid `## [Unreleased]` header
- [ ] `.gitignore` prevents accidental secret commits
- [ ] LICENSE file present

##### Story: OS Detection Library

**Summary**: `lib/platform.sh` — sourced bash functions: `source_os_release`, `pkg_install`, `pkg_repo_add`, `is_gnome`, `die_if_unsupported_os`.

**Implementation steps**:
1. Create `lib/platform.sh`
2. Implement `source_os_release`: reads `/etc/os-release`, exports `OS_ID`, `OS_MAJOR_VERSION`
3. Implement `pkg_install()`: dispatches to apt-get or dnf
4. Implement `pkg_repo_add(url, keyring_url, name)`: handles apt + yum repo addition
5. Implement `is_gnome()`: boolean
6. Implement `die_if_unsupported_os()`: aborts cleanly

**Test procedures**: IT-01, unit tests with mocked `/etc/os-release`.

**Acceptance criteria**:
- [ ] Ubuntu 24.04 → `OS_ID=ubuntu`, `OS_MAJOR_VERSION=24`
- [ ] Rocky 9 → `OS_ID=rocky`, `OS_MAJOR_VERSION=9`
- [ ] `pkg_install foo` produces correct apt-get/dnf command
- [ ] `die_if_unsupported_os` exits non-zero on Debian 11
- [ ] Passes shellcheck
- [ ] bats-core suite covers supported + unsupported

#### Wave 1.2 — Entry Point + Makefile (depends on Wave 1.1)

##### Story: install.sh Bootstrap

**Summary**: ~100-line entry point with flag parsing, pre-flight, prereq install, chezmoi init + apply.

**Implementation steps**:
1. Source `lib/platform.sh`
2. Parse flags: `--dry-run`, `--role=<X>`, `--skip-secrets`, `--allow-root`, `--help`
3. Pre-flight: EUID, network to github.com, supported OS, curl/git/bash presence
4. Install prereqs: chezmoi, rbw, direnv, pinentry-curses (always), pinentry-gnome3 (if GNOME)
5. Run `chezmoi init https://github.com/bakeb7j0/beget --data "role=$role"`
6. If not `--skip-secrets`, check `rbw status`, prompt login if needed
7. Run `chezmoi apply [--dry-run]`
8. Report completion and next-step hint

**Test procedures**: E2E-01, E2E-03, E2E-08, IT-01.

**Acceptance criteria**:
- [ ] All 5 flags documented in `--help`
- [ ] Rejects root unless `--allow-root` (R-03)
- [ ] Aborts on unsupported OS clearly (R-02)
- [ ] Completes on Ubuntu 24.04 with `--skip-secrets` (E2E-01)
- [ ] Completes on Rocky 9 with `--skip-secrets` (E2E-03)
- [ ] Re-runnable without side effects (E2E-05, R-07)
- [ ] Passes shellcheck

##### Story: Makefile Core Targets

**Summary**: `Makefile` with `lint`, `apply-dry`, `apply`, `verify` targets. `test` added in Phase 3.

**Implementation steps**:
1. `lint` → shellcheck on `install.sh`, `lib/*.sh`, `run_onchange_*`
2. `apply-dry` → `chezmoi apply --dry-run --verbose`
3. `apply` → `chezmoi apply --verbose`
4. `verify` → `chezmoi verify` with diff report
5. `help` → lists all targets with descriptions
6. `.PHONY` declarations for all targets

**Test procedures**: IT-08.

**Acceptance criteria**:
- [ ] `make` shows help
- [ ] `make lint` fails on shellcheck violations
- [ ] `make apply-dry` produces output without mutation
- [ ] `make verify` reports drift

#### Wave 1.3 — Baseline Dotfiles + Identity (depends on Wave 1.2, parallel)

##### Story: Minimal Dotfiles

**Summary**: Baseline dotfiles materialized by chezmoi — working shell after bootstrap.

**Implementation steps**:
1. Port `.bashrc` (minus secret-dependent exports)
2. Create `dot_bashrc.d/10-common.sh` (colored aliases, PATH additions, zoxide, fzf)
3. Port `.bash_aliases`
4. Create `dot_config/ghostty/config` (IBM CGA theme)
5. Create `dot_config/tmux/tmux.conf` + `dot_config/tmux/scripts/`
6. Create `dot_config/direnv/config.toml` (no implicit whitelist)
7. Create `dot_profile`, `dot_inputrc` as appropriate

**Test procedures**: E2E-01, MV-01.

**Acceptance criteria**:
- [ ] Fresh shell has working prompt
- [ ] Aliases (`ls`, `ll`, `vi`) work
- [ ] PATH includes `~/.local/bin`, `~/.cargo/bin`
- [ ] tmux starts with CGA theme and correct prefix (`C-Space`)
- [ ] Ghostty opens with IBM CGA theme
- [ ] No secret-dependent env vars referenced

##### Story: Git Identity with includeIf

**Summary**: `dot_gitconfig.tmpl` + `dot_gitconfig-analogic` providing per-repo identity.

**Implementation steps**:
1. Create `dot_gitconfig.tmpl` with default personal `[user]`, `[filter "lfs"]`, `[core]`, and `[includeIf "hasconfig:remote.*.url:git@gitlab.com:analogicdev/**"] path = ~/.gitconfig-analogic`
2. Create `dot_gitconfig-analogic` overriding `user.email = brbaker@analogic.com`
3. Resolve canonical default personal identity (`brian@waveeng.com` or alternate)

**Test procedures**: MV-09.

**Acceptance criteria**:
- [ ] `git config user.email` in analogicdev repo → Analogic email (R-24)
- [ ] `git config user.email` in personal repo → personal email (R-25)
- [ ] `includeIf` matcher uses git ≥2.36 syntax correctly
- [ ] No credentials in either file

**Wave structure for Phase 1**:

| Wave | Stories | Dependencies | Parallel? |
|---|---|---|---|
| 1.1 | Repo Scaffolding, OS Detection Library | None | Yes |
| 1.2 | install.sh Bootstrap, Makefile Core Targets | Wave 1.1 | Yes |
| 1.3 | Minimal Dotfiles, Git Identity | Wave 1.2 | Yes |

---

### Phase 2 — Secrets and Operational Docs

**Phase DoD**: rbw integration live. SSH keys and AWS credentials materialize from VW via chezmoi templates. `newsecret` works end-to-end. Migration script has moved all shell-env-var secrets into VW with verified sha256 roundtrip. Runbook documents every Section 4 flow.

#### Wave 2.1 — Shell Helpers (gate)

##### Story: Shell Secret Helpers + Tool Wrappers

**Summary**: `secret`, `secret_get`, and `gh`/`glab`/`bao` wrappers.

**Implementation steps**:
1. Create `dot_bashrc.d/executable_50-wrappers.sh`
2. Define `_secret_file_from_var()` — name conversion
3. Define `secret()` — lazy materialization with override-arg support
4. Define `secret_get()` — stdout retrieval, no export
5. Define `gh()`, `glab()`, `bao()` with propagating failure (`|| return 1`)
6. Source from `dot_bashrc` with guard
7. Remove 14 eager `export X=$(cat ~/secrets/Y)` lines from `dot_bashrc`

**Test procedures**: IT-04, IT-05, IT-06, MV-01.

**Acceptance criteria**:
- [ ] `secret GITHUB_PAT` materializes only if empty (R-13)
- [ ] `secret_get VAR` prints without mutating env (R-14)
- [ ] Name conversion correct (R-15)
- [ ] `gh pr list` materializes on first call, reuses on second (R-16)
- [ ] Failure propagation — tool doesn't run with empty auth
- [ ] Passes shellcheck
- [ ] bats-core covers: missing item, rbw locked, rbw unreachable

#### Wave 2.2 — File Templates + newsecret (depends on 2.1, parallel)

##### Story: SSH Key Chezmoi Templates

**Summary**: Templates under `private_dot_ssh/` for each SSH identity.

**Implementation steps**:
1. Create VW SSH Key items for each identity (documented)
2. Create `private_dot_ssh/id_ed25519.tmpl` (personal)
3. Create `private_dot_ssh/id_ed25519_blueshift_{dev,test,prod}.tmpl`
4. Create `private_dot_ssh/id_ed25519_{analogic,waveeng}_gitlab.tmpl`
5. Rewrite `private_dot_ssh/config` with ordered Host blocks + new file names
6. Add companion `.pub` files (non-secret)

**Test procedures**: E2E-04, MV-08.

**Acceptance criteria**:
- [ ] Materializes with 0600 (R-17)
- [ ] `~/.ssh/config` uses new names
- [ ] Ordering: `*.dev.blueshift.plus` + `*.test.blueshift.plus` before `*.blueshift.plus`
- [ ] Rotation: update VW + `chezmoi apply` → file updates (R-19)
- [ ] `ssh-keygen -l` validates each file

##### Story: AWS Credentials Chezmoi Template

**Summary**: `private_dot_aws/credentials.tmpl` for long-lived-cred profiles.

**Implementation steps**:
1. Review Catalog Section B, identify long-lived-cred profiles
2. Create VW `aws-<profile>` Logins (username=AccessKeyId, password=SecretAccessKey)
3. Create `private_dot_aws/credentials.tmpl` iterating profile list
4. Create `private_dot_aws/config` (non-secret, SSO profiles intact)

**Test procedures**: E2E-04, manual `aws sts get-caller-identity`.

**Acceptance criteria**:
- [ ] Materialized with 0600 (R-18)
- [ ] Every long-lived-creds profile has VW item
- [ ] `aws --profile <X> sts get-caller-identity` succeeds
- [ ] SSO still works
- [ ] Rotation verified

##### Story: `newsecret` Helper

**Summary**: User-facing tool for adding secrets to VW.

**Implementation steps**:
1. Create `dot_local/bin/newsecret`
2. Validate arg (non-empty, no whitespace)
3. Check `rbw get` — error on duplicate
4. Prompt + read stdin
5. Reject empty value
6. `rbw add <name>` with piped value
7. Report derived env var name

**Test procedures**: IT-07, MV-03.

**Acceptance criteria**:
- [ ] No-arg usage → exit 1
- [ ] Duplicate name → clear error
- [ ] Empty stdin → rejected
- [ ] VW Login created with password field
- [ ] Derived env-var name reported
- [ ] Passes shellcheck + bats-core

#### Wave 2.3 — Migration + direnv (depends on 2.2)

##### Story: Secrets Migration Script

**Summary**: One-shot tool to migrate `~/.secrets/` to VW with sha256 verification.

**Implementation steps**:
1. Create `scripts/migrate-secrets.sh`
2. Iterate over files in `~/.secrets/` (or `~/secrets/`)
3. Per file: sha256; check VW; compare if exists; create if not
4. Verify sha256 roundtrip post-create
5. Do NOT delete source files (manual step)
6. Summary: migrated / skipped / failed

**Test procedures**: MV-based on malory.

**Acceptance criteria**:
- [ ] Dry-run supported (`--dry-run`)
- [ ] Every file → verified VW item
- [ ] No automatic deletion
- [ ] Graceful rbw-locked handling
- [ ] Passes shellcheck
- [ ] Clear summary output

##### Story: direnv Setup + Analogic Context

**Summary**: `direnv` config + sample `.envrc`.

**Implementation steps**:
1. Confirm direnv in apt prereq list
2. Create `dot_config/direnv/config.toml` (no implicit whitelist)
3. Add `eval "$(direnv hook bash)"` to `dot_bashrc.d/10-common.sh`
4. Create `.envrc` template for Analogic tree (location TBD, documented in runbook)
5. Document pattern in runbook

**Test procedures**: MV-04.

**Acceptance criteria**:
- [ ] direnv hook active in interactive shells (R-27, R-28)
- [ ] Un-authorized `.envrc` → direnv prompts, not silent
- [ ] Example `.envrc` demonstrates context-scoped secret pattern
- [ ] After `direnv allow`, enter → load; leave → unload

#### Wave 2.4 — Documentation (depends on 2.3)

##### Story: Operations Runbook

**Summary**: `docs/runbook.md` documenting every normative flow.

**Implementation steps**:
1. Create sections for each Section 4 flow (4.2–4.7)
2. Per section: preconditions, exact commands, expected output, troubleshooting
3. Additional: `newsecret` usage, key rotation, role change, adding new machine, adding new context

**Test procedures**: BJ reviews end-to-end on a fresh VM.

**Acceptance criteria**:
- [ ] Every Section 4 flow has runbook section with copy-pasteable commands
- [ ] Commands work verbatim
- [ ] Troubleshooting covers: rbw locked, VW unreachable, chezmoi conflicts, direnv not authorized
- [ ] Cross-linked to Dev Spec sections

##### Story: Deployment Verification Checklist

**Summary**: `docs/deployment-verification.md` — post-install sanity checks.

**Implementation steps**:
1. Create checklist: shell sources, PATH effective, wrappers fire, git identity, direnv, systemd units, SSH keys with perms, AWS creds usable
2. Format for paste into PR description or issue

**Test procedures**: BJ uses after MV-01.

**Acceptance criteria**:
- [ ] ≥10 concrete verification items
- [ ] Each has exact command + expected output
- [ ] Organized: shell / tools / secrets / system

**Wave structure for Phase 2**:

| Wave | Stories | Dependencies | Parallel? |
|---|---|---|---|
| 2.1 | Shell Helpers | Phase 1 complete | Single |
| 2.2 | SSH Templates, AWS Template, newsecret | Wave 2.1 | Yes |
| 2.3 | Migration Script, direnv Setup | Wave 2.2 | Yes |
| 2.4 | Runbook, Deployment Verification | Wave 2.3 | Yes |

---

### Phase 3 — Full Migration + CI

**Phase DoD**: Every Asset Catalog asset installed on a fresh machine. System-level config applied. Upstream projects cloned and installed. CI green. All 27 test cases runnable and passing. VRTM traces every R-XX. Manual verification procedures documented.

#### Wave 3.1 — System-Level Infrastructure (parallel, depends on Phase 2)

##### Story: APT Package Lists

**Summary**: Canonical newline-delimited package lists, role-scoped.

**Implementation steps**:
1. Create `share/apt-packages-common.list` (dev CLIs, git/jq/fzf, docker, shellcheck)
2. Create `share/apt-packages-workstation.list` (GUI/desktop)
3. Create `share/apt-packages-server.list` (server-focused)
4. Create `share/apt-packages-minimal.list` (git, curl, bash, ca-certificates)
5. Group with `#` comments by category
6. Create `run_onchange_before_20-packages-common.sh` that reads lists and invokes `pkg_install`

**Test procedures**: IT-01, E2E-02, E2E-03.

**Acceptance criteria**:
- [ ] common.list ≥20 base packages
- [ ] workstation.list covers GUI/desktop from Catalog K
- [ ] Script runs `apt-get install -y` on Ubuntu; equivalent on RHEL
- [ ] Role scoping: minimal installs only minimal; workstation installs common + workstation
- [ ] Idempotent

##### Story: APT Repo Management

**Summary**: `run_onchange_before_10-apt-repos.sh` adds 10+ user repos.

**Implementation steps**:
1. Create `run_onchange_before_10-apt-repos.sh`
2. Local array `(name → {url, keyring_url, sources_line})`
3. Per repo: download keyring to `/etc/apt/keyrings/<name>.gpg`, write sources.list.d file, run `apt update` at end
4. Cover: Mozilla Firefox, google-chrome, vivaldi, slack, spotify, wezterm, hashicorp, vscode, synaptics, nextcloud-devs, xtradeb-apps
5. RHEL equivalent: `run_onchange_before_10-dnf-repos.sh`

**Test procedures**: IT-01, E2E-02.

**Acceptance criteria**:
- [ ] Fresh Ubuntu → all 10+ repos added
- [ ] GPG keys in `/etc/apt/keyrings/`
- [ ] `apt update` clean after
- [ ] Idempotent
- [ ] Fails clean on 404 (no partial state)

##### Story: sysctl Configuration

**Summary**: `run_onchange_before_30-sysctl.sh` + `share/sysctl.d/` files.

**Implementation steps**:
1. Create `share/sysctl.d/10-map-count.conf` (`vm.max_map_count=1048576`)
2. Create `share/sysctl.d/60-carbonyl-userns.conf` (`kernel.apparmor_restrict_unprivileged_userns=0`)
3. Create `run_onchange_before_30-sysctl.sh` → sudo-copy, `sysctl --system`
4. Header comments explain purposes

**Test procedures**: IT-01, manual sysctl query.

**Acceptance criteria**:
- [ ] Both files in `/etc/sysctl.d/`
- [ ] Values active via `sysctl`
- [ ] Idempotent
- [ ] Comments explain what/why

#### Wave 3.2 — Services, Tooling, GNOME, Upstream (parallel, depends on 3.1)

##### Story: systemd Units (User + System)

**Summary**: 2 user units + 3 system units (workstation-scoped).

**Implementation steps**:
1. Create `share/systemd/user/gnome-shell-rss-sample.{service,timer}`
2. Create `share/systemd/user/restart-xdg-portal.{service,timer}`
3. Create `share/systemd/system/{node_exporter,ttyd-sesh,chronyd}.service`
4. Create `run_onchange_before_40-systemd-user.sh`
5. Create `run_onchange_before_41-systemd-system.sh` (tag-scoped, sudo)
6. Unit files carry header comments (BUG-WORKAROUND flags where relevant)

**Test procedures**: IT-01, `systemctl --user list-unit-files`, `sudo systemctl list-unit-files`.

**Acceptance criteria**:
- [ ] 2 user units enabled in `~/.config/systemd/user/`
- [ ] 3 system units enabled (workstation only) in `/etc/systemd/system/`
- [ ] `daemon-reload` runs after install
- [ ] Idempotent
- [ ] `restart-xdg-portal` prominently flagged as workaround

##### Story: Non-apt Tooling Installation

**Summary**: Per-pattern install scripts (download, shell-installer, pipx, tarball).

**Implementation steps**:
1. `run_onchange_before_50-tool-download-binaries.sh`: aws, kubectl, sops, yq, trivy, rclone, crane, dockle, firebase, dictate, bw, sesh
2. `run_onchange_before_51-tool-shell-installers.sh`: rustup, bun, nvm
3. `run_onchange_before_52-tool-pipx.sh`: yamllint, yt-dlp, gl-settings, kairos-contracts
4. `run_onchange_before_53-tool-uv.sh`: dvc
5. `run_onchange_before_54-tool-claude-code.sh`: Claude Code CLI
6. `run_onchange_before_55-tool-carbonyl.sh`: carbonyl tarball
7. `run_onchange_before_56-tool-go.sh`: Go toolchain + shfmt
8. Each: source URL, checksum (pinned), version (pinned)

**Test procedures**: IT-01 per script, E2E-04 (binary --version).

**Acceptance criteria**:
- [ ] Every Catalog L binary has install script
- [ ] Each documents source, version, checksum
- [ ] Idempotent (skips correct-version installs)
- [ ] Fails clean on 404/checksum mismatch
- [ ] `--version` returns expected post-install

##### Story: GNOME Keybindings

**Summary**: `run_onchange_before_workstation_70-gnome-keybinds.sh` sets 3 cheet-popup bindings.

**Implementation steps**:
1. Use `gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings`
2. Define 3 triples: Ctrl+F1 → tldr, Alt+F1 → cheat, Ctrl+Alt+F1 → both
3. Script iterates setting name/command/shortcut per binding
4. Tag-scoped to workstation

**Test procedures**: IT-01, MV (press keys).

**Acceptance criteria**:
- [ ] All 3 bindings present in Settings post-apply
- [ ] Each combo invokes `cheet-popup.sh` with correct arg
- [ ] Idempotent (no duplicates)
- [ ] Handles pre-existing-binding case (no overwrites)

##### Story: Upstream Project Integrations

**Summary**: `.chezmoiexternal.toml` + post-clone installer.

**Implementation steps**:
1. Create `.chezmoiexternal.toml` with 5 projects
2. Create `run_onchange_after_90-upstream-install.sh` iterating and invoking install.sh
3. Follow-up list: upstream projects lacking one-line installers

**Test procedures**: IT-01, MV-10.

**Acceptance criteria**:
- [ ] All 5 upstream repos cloned to `~/.local/share/<name>/` (R-36)
- [ ] `install.sh` invoked where present (R-37)
- [ ] 168h refresh period
- [ ] Follow-ups opened for missing installers

#### Wave 3.3 — Test Infrastructure and CI (parallel, depends on 3.2)

##### Story: GitHub Actions CI Pipeline

**Summary**: `.github/workflows/ci.yml` invoking `make` targets.

**Implementation steps**:
1. Trigger on PR + push to main
2. Jobs: lint, template-render, unit, e2e-ubuntu, e2e-rocky
3. Use standard actions; cache chezmoi/bats/shellcheck
4. Upload JUnit XML artifacts

**Test procedures**: CI on trivial PR.

**Acceptance criteria**:
- [ ] Triggers on PR + main push
- [ ] 5 jobs passing on empty-changes PR
- [ ] JUnit XML artifacts (DM-05)
- [ ] Each job under 10 minutes

##### Story: Unit Test Suite (bats-core)

**Summary**: `tests/unit/*.bats` for all bash helpers.

**Implementation steps**:
1. `tests/unit/secret.bats` — IT-04, IT-05, IT-06, IT-07
2. `tests/unit/platform.bats` — platform.sh function tests with mocked `/etc/os-release`
3. `tests/unit/os-detection.bats` — OS version edge cases
4. `tests/helpers/mocks.sh` — mock helpers (mock_rbw, mock_os_release)

**Test procedures**: `make test-unit`, CI.

**Acceptance criteria**:
- [ ] Every public helper ≥1 positive + ≥1 negative test
- [ ] Passes via `bats tests/unit/*.bats`
- [ ] Helpers don't mutate machine state
- [ ] JUnit XML generated

##### Story: Integration Test Suite

**Summary**: `tests/integration/` — static analysis + template rendering.

**Implementation steps**:
1. `tests/integration/shellcheck.sh` — all `*.sh`, aggregate failures
2. `tests/integration/shfmt.sh` — `shfmt --diff`, any diff = fail
3. `tests/integration/chezmoi-render.sh` — temp target, dry-run with fixtures
4. `tests/integration/header-comments.sh` — verify run_onchange headers
5. Makefile target: `make test-integration`

**Test procedures**: IT-01, IT-02, IT-03, IT-09.

**Acceptance criteria**:
- [ ] `make test-integration` runs all 4
- [ ] Pass/fail with offending file/line on failure
- [ ] Integrated into CI as distinct job

##### Story: E2E Test Suite (Containerized)

**Summary**: `tests/e2e/` — docker-based smoke tests.

**Implementation steps**:
1. `tests/e2e/Dockerfile.{ubuntu24,rocky9}`
2. `tests/e2e/e2e-XX-*.sh` for each E2E-01 through E2E-08
3. Each outputs JUnit XML
4. Fresh container per test

**Test procedures**: E2E-01 through E2E-08.

**Acceptance criteria**:
- [ ] All 8 pass in CI
- [ ] Each isolated (no shared state)
- [ ] Total wall-time < 10 minutes
- [ ] JUnit XML generated

##### Story: Makefile test Target + Result Aggregation

**Summary**: Makefile wiring for test tiers.

**Implementation steps**:
1. `test-unit` → bats on `tests/unit/`
2. `test-integration` → 4 integration scripts
3. `test-e2e` → builds containers, runs E2E
4. `test` → all three
5. `test-quick` → unit + integration only (< 30s)
6. Results to `tests/results/` (gitignored)

**Test procedures**: IT-08.

**Acceptance criteria**:
- [ ] `make test` runs three tiers
- [ ] `make test-quick` < 30s on workstation
- [ ] Results in `tests/results/`
- [ ] `make help` documents each target

#### Wave 3.4 — Traceability and Verification Docs (parallel, depends on 3.3)

##### Story: VRTM

**Summary**: `docs/beget-vrtm.md` mapping R-XX → verifications.

**Implementation steps**:
1. Create `docs/beget-vrtm.md` table
2. Fill every R-01–R-46 with test IDs or flow references
3. Flag untraced requirements; fix or mark with rationale

**Test procedures**: BJ review; mechanical: every R-XX appears.

**Acceptance criteria**:
- [ ] Every R-XX has VRTM row
- [ ] Every row ≥1 test/flow reference
- [ ] Zero "untraced"
- [ ] Committed and linked from README

##### Story: Manual Verification Procedures Document

**Summary**: `docs/manual-verification.md` for all MV-XX.

**Implementation steps**:
1. One section per MV-XX (MV-01–MV-10)
2. Preconditions, step-by-step commands, expected output, PASS/FAIL criteria
3. Format for paste into issues
4. Cross-link from runbook

**Test procedures**: BJ review; optional: execute one MV end-to-end.

**Acceptance criteria**:
- [ ] All 10 MV-XX have detailed procedures
- [ ] Each ≤15 steps
- [ ] Pass/fail criteria objective
- [ ] Cross-referenced from runbook and README

**Wave structure for Phase 3**:

| Wave | Stories | Dependencies | Parallel? |
|---|---|---|---|
| 3.1 | APT Packages, APT Repos, sysctl | Phase 2 complete | Yes |
| 3.2 | systemd Units, Non-apt Tooling, GNOME Keybindings, Upstream Integrations | Wave 3.1 | Yes |
| 3.3 | CI Pipeline, Unit Tests, Integration Tests, E2E Tests, Makefile test Target | Wave 3.2 | Yes |
| 3.4 | VRTM, Manual Verification Doc | Wave 3.3 | Yes |

**Total**: 28 stories across 10 waves and 3 phases.

---

## 9. Appendices

### Appendix V — VRTM Skeleton

Template for the Verification/Validation Requirements Traceability Matrix (DM-08), populated in Phase 3.

| Req ID | Summary | Category | Verifying Test IDs | Section 4 Flow | Notes |
|---|---|---|---|---|---|
| R-01 | curl\|bash bootstrap installs prereqs | Bootstrap | E2E-01, IT-08 | §4.2 | |
| R-02 | Abort on unsupported OS | Bootstrap | IT-01, unit test for `die_if_unsupported_os` | §4.2 | |
| R-03 | Abort if running as root | Bootstrap | E2E-08 | §4.2 | |
| ... | *populated in Phase 3* | | | | |
| R-46 | CHANGELOG.md present | Docs | Manual | — | |

**Policy**: Every R-XX must have ≥1 entry in "Verifying Test IDs" or "Section 4 Flow" by Phase 3 completion. Rows with neither are blocking.

### Appendix G — Glossary

| Term | Definition |
|---|---|
| **beget** | This project |
| **chezmoi** | Dotfile manager with templates, secret integration |
| **rbw** | Rust Bitwarden client with local encrypted cache |
| **Vaultwarden** | Self-hosted Bitwarden-compatible server |
| **direnv** | Per-directory environment loader |
| **bats-core** | Bash Automated Testing System |
| **shellcheck** | Static analyzer for shell scripts |
| **shfmt** | Shell script formatter |
| **EARS** | Easy Approach to Requirements Syntax |
| **VRTM** | Verification/Validation Requirements Traceability Matrix |
| **includeIf** | Git config conditional include |
| **hasconfig:remote.\*.url:** | `includeIf` matcher based on remote URL (Git ≥2.36) |
| **Secret Service** | DBus API for password storage (GNOME keyring, KWallet) |
| **pinentry** | GPG-family password prompt UI |
| **rbw-agent** | Long-running process caching VW master password |
| **role** | chezmoi data value (`workstation`/`server`/`minimal`) |
| **activity context** | Runtime-scoped identity (Analogic / waveeng / personal) |
| **run_onchange** | chezmoi script prefix; executes on content change |
| **Tier 1/2/3** | Deliverables Manifest tiers |
| **Dev Spec** | This document |
| **DoD** | Definition of Done |
| **MV** | Manual Verification |
| **IT** | Integration Test |
| **E2E** | End-to-End test |

### Appendix R — References

**Tools**:
- chezmoi: https://chezmoi.io
- rbw: https://github.com/doy/rbw
- Vaultwarden: https://github.com/dani-garcia/vaultwarden
- direnv: https://direnv.net
- bats-core: https://github.com/bats-core/bats-core
- shellcheck: https://www.shellcheck.net
- shfmt: https://github.com/mvdan/sh

**Specifications**:
- EARS pattern: Mavin et al., "Easy Approach to Requirements Syntax"
- Git `hasconfig:remote.*.url:` matcher: https://git-scm.com/docs/git-config#_conditional_includes
- Secret Service API: https://specifications.freedesktop.org/secret-service/latest/

**Internal**:
- Sketchbook: `~/sysadmin/unresolved-issues/beget-sketchbook.md` (superseded by this Dev Spec)
- Asset inventory subagent report: session history 2026-04-20
- Secrets migration plan (81-file inventory): session history 2026-04-20
