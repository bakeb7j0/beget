#!/usr/bin/env bash
# scripts/ci/run-e2e.sh — run the E2E smoke suite for a given distro image.
#
# Usage: scripts/ci/run-e2e.sh <distro>
# where <distro> matches a Dockerfile.<distro> under tests/e2e/.
#
# Single engine for E2E: CI calls it per-distro as separate jobs; `make
# test-e2e` calls it for both distros (or one, if DISTRO is set). Do not
# add a delegation-to-make guard here — it would recurse.
set -euo pipefail

distro="${1:?distro argument required (ubuntu24 | rocky9)}"

mkdir -p tests/results

dockerfile="tests/e2e/Dockerfile.${distro}"
if [[ ! -f "$dockerfile" ]]; then
    echo "e2e: no Dockerfile.$distro found (pending Story #28) — skipping" >&2
    # Emit an empty-but-valid JUnit file so artifact upload has something.
    cat >"tests/results/e2e-${distro}.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<testsuites name="e2e-${distro}" tests="0" failures="0" errors="0" skipped="0"/>
EOF
    exit 0
fi

image="beget-e2e:${distro}"
docker build -f "$dockerfile" -t "$image" .

shopt -s nullglob
scripts=(tests/e2e/e2e-*.sh)
if [[ ${#scripts[@]} -eq 0 ]]; then
    echo "e2e: no e2e-XX-*.sh scripts yet (pending Story #28)" >&2
    exit 0
fi

# Distro filter: a script whose filename contains `-ubuntu-` OR ends in
# `-ubuntu` runs only on ubuntu* images; `-rocky-` or `-rocky` suffix runs
# only on rocky* images; everything else runs on both. The convention is
# part of the filename so filtering stays obvious at the call site.
distro_family="${distro%%[0-9]*}"

fail=0
for s in "${scripts[@]}"; do
    name="$(basename "$s" .sh)"
    case "$name" in
        *-ubuntu-* | *-ubuntu) [[ "$distro_family" == "ubuntu" ]] || {
            echo "--- $name skipped on $distro ---"
            continue
        } ;;
        *-rocky-* | *-rocky) [[ "$distro_family" == "rocky" ]] || {
            echo "--- $name skipped on $distro ---"
            continue
        } ;;
    esac
    printf '\n=== %s on %s ===\n' "$name" "$distro"
    # No --privileged: the e2e scripts under tests/e2e/ don't touch systemd or
    # devices. If a future test needs a specific capability, add it narrowly
    # (--cap-add=...) with justification rather than re-enabling --privileged.
    #
    # Two --user modes:
    #   - Dry-run / source-only tests (e2e-01..e2e-08): run as host uid/gid so
    #     JUnit writes to the bind-mounted tests/results/ without extra perms
    #     fiddling. These tests never invoke sudo/apt.
    #   - Real-install tests (e2e-09+, whose filenames contain `-oneliner-`
    #     or `-chezmoi-apply-`): MUST run as the Dockerfile's beget user
    #     (uid 1000) because install.sh calls `sudo apt-get install` and
    #     sudo requires a /etc/passwd entry matching the runtime uid. The
    #     host uid on CI runners typically isn't 1000 and isn't in passwd,
    #     so sudo fails with "you do not exist in the passwd database".
    #     tests/results/ is made world-writable beforehand so the uid-1000
    #     write from emit_junit succeeds on the bind mount.
    # The non-root path (R-03) relies on euid != 0, which any non-zero uid
    # satisfies; e2e-08 stubs current_euid() rather than using the real uid.
    case "$name" in
        *-oneliner-* | *-chezmoi-apply-*)
            chmod 777 tests/results
            # -e HOME: docker --user switches uid but doesn't source the
            # user's profile, so $HOME would otherwise default to / and
            # install.sh's $HOME/.local/bin writes would land in root's
            # filesystem.
            docker_args=(--user 1000:1000 -e HOME=/home/beget)
            ;;
        *)
            docker_args=(--user "$(id -u):$(id -g)")
            ;;
    esac
    if ! docker run --rm "${docker_args[@]}" -v "$PWD:/src" -w /src "$image" bash "$s"; then
        fail=1
    fi
done
exit "$fail"
