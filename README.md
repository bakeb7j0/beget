# beget

BJ's personal machine bootstrap via chezmoi. This repo encodes one developer's
specific Linux working environment as a reproducible bootstrap. It is **not** a
generic dev-environment tool — it is a serialized description of one person's
setup, not a parameterized framework.

> **Look but don't touch.** This is a solo-maintained personal bootstrap repo.
> External PRs will not be merged. Feel free to fork it and adapt patterns to
> your own setup — that's an incidental benefit, not a design goal.

## Status

**Under construction.** The approved Development Specification describing the
full intended architecture and phased implementation plan lives at
[`docs/beget-devspec.md`](docs/beget-devspec.md).

The Dev Spec covers:

- Problem domain, target users, non-goals
- Technical and product constraints
- 46 functional requirements (EARS format)
- System context and 6 operational flows
- Detailed design across 9 topic areas
- Test plan (27 tests across 3 tiers)
- Definition of Done
- Phased implementation plan: 28 stories across 11 waves and 3 phases

## Install

The bootstrap is a two-step install: a one-time root step that lays down the
distro packages beget's toolchain depends on, then a user-local step that does
everything else.

**Step 1 — distro prerequisites (one-time, runs as root):**

```bash
curl -fsSL https://github.com/bakeb7j0/beget/raw/HEAD/scripts/install-prereqs.sh | sudo bash
```

This installs packages that can only come from the system package manager:
`pinentry` (for GPG/rbw prompts), `pkg-config` and the OpenSSL dev headers +
C toolchain (needed by `cargo install rbw`), plus the small set of userland
tools (`git`, `curl`) beget itself shells out to. On Rocky 9 it also enables
EPEL and CodeReady Builder. See [`scripts/install-prereqs.sh`](scripts/install-prereqs.sh)
for the full per-distro package list.

**Step 2 — user-local install (no sudo needed):**

```bash
curl -fsSL https://github.com/bakeb7j0/beget/raw/HEAD/install.sh | bash
```

`install.sh` installs chezmoi, direnv, rbw, and everything else into
`~/.local/bin` / `~/.cargo/bin`, clones this repo, and applies chezmoi. It
scans for the step-1 prerequisites up front and exits with actionable guidance
if anything is missing — it **never** calls `sudo` itself, which means the
one-liner is safe to run non-interactively (CI, containers without passwordless
sudo, etc.).

CI and automation paths that know the host is already prepped can pass
`--skip-prereqs` to bypass the up-front scan.

## Prerequisites

_Stub — detailed prerequisites will be documented as stories land._

- A supported Linux distribution (see [Supported Platforms](#supported-platforms))
- `git`, `curl`, and `bash` available on the target host (`install-prereqs.sh`
  provides `git` and `curl`; a minimal bootstrap needs `curl` + `bash` to
  fetch step 1).
- Network access to GitHub for fetching this repo and its dependencies

## Supported Platforms

- Ubuntu 24.04 LTS+
- RHEL 9+ and family (Fedora current, Rocky Linux 9+, AlmaLinux 9+)

Linux only. No macOS, Windows, or BSD support.

## Documentation

- [Development Specification](docs/beget-devspec.md) — problem domain,
  requirements (R-01..R-46), flows, and phased implementation plan.
- [Verification Traceability Matrix](docs/beget-vrtm.md) — every
  requirement traced to its verifying test, flow, or inspection artifact.
- [Runbook](docs/runbook.md) — day-to-day operational procedures.
- [Manual Verification Procedures](docs/manual-verification.md) — ten
  paste-into-an-issue procedures (MV-01..MV-10) for flows that cannot be
  automated.
- [Deployment Verification](docs/deployment-verification.md) — post-deploy
  smoke checklist.

## License

MIT. See [`LICENSE`](LICENSE).
