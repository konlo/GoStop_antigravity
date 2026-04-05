#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_DIR="$ROOT_DIR/test_artifacts"
DRY_RUN=1
FAIL_DAYS=14
TMP_DAYS=7

usage() {
    cat <<'EOF'
Usage: scripts/cleanup_artifacts.sh [--apply] [--fail-days N] [--tmp-days N]

Default mode is dry-run. The script:
- ensures the standard artifact directories exist
- reports top-level disk usage under test_artifacts/
- finds old directories in test_artifacts/tmp/
- finds old FAIL run directories that contain summary.md with "Success: FAIL"

Options:
  --apply         Delete the reported candidates instead of printing them.
  --fail-days N   Age threshold in days for FAIL run directories. Default: 14
  --tmp-days N    Age threshold in days for tmp directories. Default: 7
  --help          Show this help text.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --apply)
            DRY_RUN=0
            shift
            ;;
        --fail-days)
            FAIL_DAYS="${2:?missing value for --fail-days}"
            shift 2
            ;;
        --tmp-days)
            TMP_DAYS="${2:?missing value for --tmp-days}"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            printf 'Unknown option: %s\n\n' "$1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

ensure_structure() {
    mkdir -p \
        "$ARTIFACT_DIR/latest" \
        "$ARTIFACT_DIR/baselines" \
        "$ARTIFACT_DIR/investigations" \
        "$ARTIFACT_DIR/archive" \
        "$ARTIFACT_DIR/tmp"
}

report_usage() {
    printf '[usage] total\n'
    du -sh "$ARTIFACT_DIR" 2>/dev/null || true
    printf '\n[usage] largest top-level directories\n'
    find "$ARTIFACT_DIR" -maxdepth 1 -mindepth 1 -type d -exec du -sh {} + 2>/dev/null | sort -h | tail -n 15 || true
}

find_tmp_candidates() {
    find "$ARTIFACT_DIR/tmp" -mindepth 1 -maxdepth 1 -type d -mtime +"$TMP_DAYS" 2>/dev/null | sort
}

find_fail_candidates() {
    find "$ARTIFACT_DIR" -type f -name summary.md \
        ! -path "$ARTIFACT_DIR/latest/*" \
        ! -path "$ARTIFACT_DIR/baselines/*" \
        ! -path "$ARTIFACT_DIR/archive/*" \
        -mtime +"$FAIL_DAYS" -print0 2>/dev/null |
        while IFS= read -r -d '' summary_file; do
            if grep -q 'Success: FAIL' "$summary_file"; then
                dirname "$summary_file"
            fi
        done | sort -u
}

delete_or_print() {
    local label="$1"
    shift
    local candidates=("$@")

    printf '\n[%s]\n' "$label"
    if [[ ${#candidates[@]} -eq 0 ]]; then
        printf 'none\n'
        return
    fi

    printf '%s\n' "${candidates[@]}"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        return
    fi

    printf 'deleting %s candidates...\n' "$label"
    rm -rf -- "${candidates[@]}"
}

main() {
    ensure_structure
    report_usage

    local tmp_candidates=()
    local fail_candidates=()
    local candidate

    while IFS= read -r candidate; do
        [[ -n "$candidate" ]] && tmp_candidates+=("$candidate")
    done < <(find_tmp_candidates)

    while IFS= read -r candidate; do
        [[ -n "$candidate" ]] && fail_candidates+=("$candidate")
    done < <(find_fail_candidates)

    if [[ ${#tmp_candidates[@]} -gt 0 ]]; then
        delete_or_print "tmp older than ${TMP_DAYS}d" "${tmp_candidates[@]}"
    else
        delete_or_print "tmp older than ${TMP_DAYS}d"
    fi

    if [[ ${#fail_candidates[@]} -gt 0 ]]; then
        delete_or_print "fail runs older than ${FAIL_DAYS}d" "${fail_candidates[@]}"
    else
        delete_or_print "fail runs older than ${FAIL_DAYS}d"
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
        printf '\nDry run only. Re-run with --apply to delete listed directories.\n'
    fi
}

main
