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

## Platform support

- Ubuntu 24.04 LTS+
- RHEL 9+ and family (Fedora current, Rocky Linux 9+, AlmaLinux 9+)

Linux only. No macOS, Windows, or BSD support.

## License

MIT. See [`LICENSE`](LICENSE).
