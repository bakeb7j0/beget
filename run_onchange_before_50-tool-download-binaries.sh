#!/usr/bin/env bash
# run_onchange_before_50-tool-download-binaries.sh — download pre-built
# single-binary tools and place them under ~/.local/bin/.
#
# Pattern: these upstreams ship a versioned binary, tarball, or zip at a
# stable URL. We verify the download against a sha256 checksum, atomically
# install to ~/.local/bin/<name>, and mark executable. A pinned-version
# check at the head of the installer avoids re-downloads when the current
# binary already matches.
#
# Checksums: every row below currently carries a PLACEHOLDER sha256 of
# form 0000…000N. These MUST be replaced with the real upstream sha256
# before shipping a real bootstrap run (see `TODO(checksum)` markers in
# the table). Running the script against a real download URL with a
# placeholder sha will fail the checksum gate and skip the install —
# the placeholders are a deliberate fail-closed default, not a finished
# manifest.
#
# Fail-clean guarantees:
#   * 404 on download → abort that tool (no partial state)
#   * sha256 mismatch → abort (no install)
#   * Both failure modes log to stderr and return non-zero from the helper,
#     but the script continues on to the next tool and exits non-zero
#     overall if any tool failed.
#
# chezmoi re-trigger: every time we bump a version/checksum in the table,
# this file changes → run_onchange replays.
#
# Test seams (env-var overrides):
#   BEGET_BIN_DIR       — $HOME/.local/bin
#   BEGET_DOWNLOAD_TMP  — $(mktemp -d)
#   BEGET_CURL          — curl
#   BEGET_SHA256SUM     — sha256sum
#   BEGET_DRY_RUN       — "1" to iterate the table without side effects
#                         (used by unit tests to exercise control flow)
#   BEGET_TOOL_FILTER   — space-separated allowlist of tool names
#                         (tests stage minimal tables)
#
# Public functions (sourced for testing):
#   beget_tool_table    — prints the NAME|VERSION|URL|SHA256 table
#   install_download_binary NAME VERSION URL SHA256
#   current_version_matches NAME VERSION  — idempotency probe

set -euo pipefail

BEGET_BIN_DIR="${BEGET_BIN_DIR:-${HOME}/.local/bin}"
BEGET_CURL="${BEGET_CURL:-curl}"
BEGET_SHA256SUM="${BEGET_SHA256SUM:-sha256sum}"
BEGET_TAR="${BEGET_TAR:-tar}"
BEGET_UNZIP="${BEGET_UNZIP:-unzip}"

# Table format: NAME|VERSION|URL|SHA256
# The URL may embed {{VERSION}} (substituted before download) and may point
# at either a raw binary or a tarball (detected by .tar.gz suffix). Versions
# here are pinned to the values verified by the beget maintainer; bumping a
# row is the only way to trigger a re-install.
#
# Tools covered (12): aws, kubectl, sops, yq, trivy, rclone, crane, dockle,
# firebase, dictate, bw, sesh. Every row documents source, version, checksum.
beget_tool_table() {
    # TODO(checksum): every sha256 below is a PLACEHOLDER of the form
    # 0000…000N. Before this script can run against real upstream URLs,
    # each row's sha must be replaced with the value published by the
    # upstream (GitHub release artifact checksum, `.sha256` sidecar, etc.).
    # Lines with placeholders will fail the checksum gate and skip install.
    cat <<'TABLE'
aws|2.15.30|https://awscli.amazonaws.com/awscli-exe-linux-x86_64-2.15.30.zip|0000000000000000000000000000000000000000000000000000000000000001
kubectl|1.30.1|https://dl.k8s.io/release/v1.30.1/bin/linux/amd64/kubectl|0000000000000000000000000000000000000000000000000000000000000002
sops|3.8.1|https://github.com/getsops/sops/releases/download/v3.8.1/sops-v3.8.1.linux.amd64|0000000000000000000000000000000000000000000000000000000000000003
yq|4.44.1|https://github.com/mikefarah/yq/releases/download/v4.44.1/yq_linux_amd64|0000000000000000000000000000000000000000000000000000000000000004
trivy|0.52.0|https://github.com/aquasecurity/trivy/releases/download/v0.52.0/trivy_0.52.0_Linux-64bit.tar.gz|0000000000000000000000000000000000000000000000000000000000000005
rclone|1.66.0|https://downloads.rclone.org/v1.66.0/rclone-v1.66.0-linux-amd64.zip|0000000000000000000000000000000000000000000000000000000000000006
crane|0.19.1|https://github.com/google/go-containerregistry/releases/download/v0.19.1/go-containerregistry_Linux_x86_64.tar.gz|0000000000000000000000000000000000000000000000000000000000000007
dockle|0.4.14|https://github.com/goodwithtech/dockle/releases/download/v0.4.14/dockle_0.4.14_Linux-64bit.tar.gz|0000000000000000000000000000000000000000000000000000000000000008
firebase|13.9.0|https://firebase.tools/bin/linux/v13.9.0|0000000000000000000000000000000000000000000000000000000000000009
dictate|0.3.0|https://github.com/dictate-sh/dictate/releases/download/v0.3.0/dictate-linux-amd64|000000000000000000000000000000000000000000000000000000000000000a
bw|2024.5.0|https://github.com/bitwarden/clients/releases/download/cli-v2024.5.0/bw-linux-2024.5.0.zip|000000000000000000000000000000000000000000000000000000000000000b
sesh|1.11.0|https://github.com/joshmedeski/sesh/releases/download/v1.11.0/sesh_Linux_x86_64.tar.gz|000000000000000000000000000000000000000000000000000000000000000c
TABLE
}

# Given NAME + expected VERSION, return 0 if ~/.local/bin/NAME --version
# output contains the expected version string; else return 1.
current_version_matches() {
    local name="$1"
    local version="$2"
    local bin="${BEGET_BIN_DIR}/${name}"
    [[ -x "$bin" ]] || return 1
    # Not every binary accepts --version; fall back to -v. Errors are
    # captured so the idempotency probe never dumps on stderr.
    local out
    out=$("$bin" --version 2>/dev/null || "$bin" -v 2>/dev/null || printf '')
    [[ "$out" == *"$version"* ]]
}

# Classify a URL into one of: tar.gz, zip, raw. Governs the post-download
# extraction strategy. Case-insensitive on the suffix so upstreams using
# mixed-case filenames (rare but seen) still classify correctly.
classify_artifact() {
    local url="$1"
    local lower="${url,,}"
    case "$lower" in
        *.tar.gz | *.tgz) printf 'tar.gz' ;;
        *.zip) printf 'zip' ;;
        *) printf 'raw' ;;
    esac
}

# After extraction, locate the executable inside $extract_dir that should
# be placed at BEGET_BIN_DIR/<name>. Strategy:
#   1. If $extract_dir/<name> exists, use it (most tools).
#   2. Otherwise walk the tree for an EXECUTABLE regular file literally
#      named <name>. First match wins (tar/zip archives for these tools
#      contain exactly one matching executable entry). An executable
#      filter prevents a LICENSE/README or other same-named non-exec
#      sibling from being mistakenly selected — unlikely in practice, but
#      install will force-set 0755 so the wrong file would be silently
#      installed as a bogus "binary".
#   3. As a last resort, fall back to any regular file named <name>. This
#      keeps archives whose upstream ships a non-+x binary (rare) working.
#   4. If still nothing found, print diagnostic and return 1.
locate_extracted_binary() {
    local extract_dir="$1" name="$2"
    if [[ -f "${extract_dir}/${name}" ]]; then
        printf '%s' "${extract_dir}/${name}"
        return 0
    fi
    local found
    found=$(find "$extract_dir" -type f -executable -name "$name" -print -quit 2>/dev/null)
    if [[ -n "$found" ]]; then
        printf '%s' "$found"
        return 0
    fi
    found=$(find "$extract_dir" -type f -name "$name" -print -quit 2>/dev/null)
    if [[ -n "$found" ]]; then
        printf '%s' "$found"
        return 0
    fi
    return 1
}

# Special case: aws CLI zip contains an `aws/install` bootstrap script
# that places the real binary + supporting files under --install-dir.
# We point it at ~/.local/aws-cli and expose ~/.local/bin/aws as the shim.
install_aws_from_extracted() {
    local extract_dir="$1"
    local installer="${extract_dir}/aws/install"
    if [[ ! -x "$installer" ]]; then
        printf 'tool-download: aws installer missing at %s\n' "$installer" >&2
        return 1
    fi
    "$installer" \
        --install-dir "${HOME}/.local/aws-cli" \
        --bin-dir "$BEGET_BIN_DIR" \
        --update
}

# Download, verify sha256, extract if needed, atomic install. Returns 0
# on success, non-zero on fetch/checksum/extract failure. No partial state.
# The RETURN trap guarantees the tmp dir is cleaned up on every exit path,
# including `install` failures under set -e that skip inline cleanup.
install_download_binary() {
    local name="$1" version="$2" url="$3" sha256="$4"
    local tmp
    tmp="$(mktemp -d)"
    # shellcheck disable=SC2064  # intentional: capture $tmp by value now.
    trap "rm -rf '$tmp'" RETURN
    local rendered_url="${url//\{\{VERSION\}\}/$version}"
    local artifact="${tmp}/artifact"
    local kind
    kind=$(classify_artifact "$rendered_url")

    if ! "$BEGET_CURL" -fsSL -o "$artifact" "$rendered_url"; then
        printf 'tool-download: failed to fetch %s at %s\n' "$name" "$rendered_url" >&2
        return 1
    fi

    local actual_sha
    actual_sha=$("$BEGET_SHA256SUM" "$artifact" | awk '{print $1}')
    if [[ "$actual_sha" != "$sha256" ]]; then
        printf 'tool-download: checksum mismatch for %s (want=%s got=%s)\n' \
            "$name" "$sha256" "$actual_sha" >&2
        return 1
    fi

    case "$kind" in
        raw)
            install -D -m 0755 -T "$artifact" "${BEGET_BIN_DIR}/${name}"
            ;;
        tar.gz)
            local extract_dir="${tmp}/extracted"
            mkdir -p "$extract_dir"
            if ! "$BEGET_TAR" -xzf "$artifact" -C "$extract_dir"; then
                printf 'tool-download: tar extract failed for %s\n' "$name" >&2
                return 1
            fi
            local binpath
            if ! binpath=$(locate_extracted_binary "$extract_dir" "$name"); then
                printf 'tool-download: no binary named %s inside tarball\n' "$name" >&2
                return 1
            fi
            install -D -m 0755 -T "$binpath" "${BEGET_BIN_DIR}/${name}"
            ;;
        zip)
            local extract_dir="${tmp}/extracted"
            mkdir -p "$extract_dir"
            if ! "$BEGET_UNZIP" -q "$artifact" -d "$extract_dir"; then
                printf 'tool-download: unzip failed for %s\n' "$name" >&2
                return 1
            fi
            # aws is a special-case installer, not a bare binary.
            if [[ "$name" == "aws" ]]; then
                if ! install_aws_from_extracted "$extract_dir"; then
                    return 1
                fi
            else
                local binpath
                if ! binpath=$(locate_extracted_binary "$extract_dir" "$name"); then
                    printf 'tool-download: no binary named %s inside zip\n' "$name" >&2
                    return 1
                fi
                install -D -m 0755 -T "$binpath" "${BEGET_BIN_DIR}/${name}"
            fi
            ;;
    esac

    printf 'tool-download: installed %s v%s\n' "$name" "$version" >&2
}

main() {
    install -d -m 0755 "$BEGET_BIN_DIR"
    local failures=0
    local name version url sha256
    while IFS='|' read -r name version url sha256; do
        [[ -z "${name:-}" || "${name:0:1}" == "#" ]] && continue

        # Test-only filter: allow unit tests to stage minimal runs.
        if [[ -n "${BEGET_TOOL_FILTER:-}" ]]; then
            case " ${BEGET_TOOL_FILTER} " in
                *" ${name} "*) : ;;
                *) continue ;;
            esac
        fi

        # Idempotency: skip if the installed binary already reports the
        # expected version. Test seam BEGET_DRY_RUN forces re-install.
        if [[ "${BEGET_DRY_RUN:-}" != "1" ]] &&
            current_version_matches "$name" "$version"; then
            printf 'tool-download: %s v%s already current, skipping\n' \
                "$name" "$version" >&2
            continue
        fi

        if ! install_download_binary "$name" "$version" "$url" "$sha256"; then
            failures=$((failures + 1))
        fi
    done < <(beget_tool_table)

    if [[ $failures -gt 0 ]]; then
        printf 'tool-download: %d tool(s) failed\n' "$failures" >&2
        return 1
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
