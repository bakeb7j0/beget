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

## One-liner install (Phase 1 target, not yet available)

```bash
curl -fsSL https://github.com/bakeb7j0/beget/raw/HEAD/install.sh | bash
```

`install.sh` is produced by Phase 1. It does not exist yet.

## Prerequisites

_Stub — detailed prerequisites will be documented as stories land._

- A supported Linux distribution (see [Supported Platforms](#supported-platforms))
- `git`, `curl`, and `bash` available on the target host
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
- [Deployment Verification](docs/deployment-verification.md) — post-deploy
  smoke checklist.

## License

MIT. See [`LICENSE`](LICENSE).
