#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_IMAGES=1
VERBOSE=0
TARGET_FILTER=""

targets=(
    "el8|developer-el8-test|el|dnf|el/8"
    "el9|developer-el9-test|el|dnf|el/9"
    "el10|developer-el10-test|el|dnf|el/10"
    "debian10|developer-debian10-test|debian|apt-get|debian/10"
    "debian11|developer-debian11-test|debian|apt-get|debian/11"
    "debian12|developer-debian12-test|debian|apt-get|debian/12"
    "debian13|developer-debian-test|debian|apt-get|debian/13"
    "ubuntu2204|developer-ubuntu2204-test|debian|apt-get|ubuntu/22.04"
    "ubuntu2404|developer-ubuntu-test|debian|apt-get|ubuntu/24.04"
    "ubuntu2604|developer-ubuntu2604-test|debian|apt-get|ubuntu/26.04"
)

usage() {
    printf 'Usage: %s [--verbose] [--no-build] [--target TARGET]\n' "$0"
    printf 'Targets:'
    for target_spec in "${targets[@]}"; do
        IFS='|' read -r target _ <<<"$target_spec"
        printf ' %s' "$target"
    done
    printf '\n'
}

while (($#)); do
    case "$1" in
        --verbose)
            VERBOSE=1
            ;;
        --no-build)
            BUILD_IMAGES=0
            ;;
        --target)
            if (($# < 2)) || [[ "$2" == -* ]]; then
                echo "Option --target requires a target name." >&2
                usage >&2
                exit 2
            fi
            TARGET_FILTER="$2"
            shift
            ;;
        --target=*)
            TARGET_FILTER="${1#*=}"
            if [[ -z "$TARGET_FILTER" ]]; then
                echo "Option --target requires a target name." >&2
                usage >&2
                exit 2
            fi
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            printf 'Unknown option: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

if [[ -n "$TARGET_FILTER" ]]; then
    target_found=0
    for target_spec in "${targets[@]}"; do
        IFS='|' read -r target _ <<<"$target_spec"
        if [[ "$target" == "$TARGET_FILTER" ]]; then
            target_found=1
            break
        fi
    done
    if (( ! target_found )); then
        printf 'Unknown target: %s\n' "$TARGET_FILTER" >&2
        usage >&2
        exit 2
    fi
fi

for required_command in docker mktemp grep sed; do
    if ! command -v "$required_command" >/dev/null 2>&1; then
        printf 'Required command is not available: %s\n' "$required_command" >&2
        exit 1
    fi
done

if ! docker info >/dev/null 2>&1; then
    echo "The Docker daemon is unreachable." >&2
    exit 1
fi

failed=0

run_target() {
    local target="$1"
    local image="$2"
    local family="$3"
    local package_manager="$4"
    local dockerfile="$5"
    local container="setup-matrix-${target}-$$"
    local build_log
    local output_log
    local container_created=0

    build_log="$(mktemp)"
    output_log="$(mktemp)"

    cleanup_target() {
        if (( container_created )); then
            docker rm -f "$container" >/dev/null 2>&1 || true
            container_created=0
        fi
        rm -f "$build_log" "$output_log"
    }

    printf '\n========== %s ==========\n' "$target"

    if (( BUILD_IMAGES )); then
        printf '[RUN] Building image %s\n' "$image"
        if ! docker build -f "${ROOT_DIR}/test/${dockerfile}/Dockerfile" -t "$image" "$ROOT_DIR" >"$build_log" 2>&1; then
            cat "$build_log"
            cleanup_target
            return 1
        fi
        if (( VERBOSE )); then
            cat "$build_log"
        fi
    fi

    printf '[RUN] Starting test container\n'
    if ! docker run -d \
        --name "$container" \
        -v "${ROOT_DIR}/setup-developer-shell.sh:/tmp/setup-developer-shell.sh:ro" \
        "$image" bash -c 'sleep infinity' >/dev/null; then
        cleanup_target
        return 1
    fi
    container_created=1

    printf '[RUN] Checking platform detection and first setup run\n'
    if ! docker exec "$container" bash /tmp/setup-developer-shell.sh >"$output_log" 2>&1; then
        cat "$output_log"
        cleanup_target
        return 1
    fi
    if (( VERBOSE )); then
        cat "$output_log"
    fi
    if ! grep -Fq "Family: ${family}; package manager: ${package_manager}" "$output_log"; then
        echo "Unexpected platform detection for $target." >&2
        cat "$output_log"
        cleanup_target
        return 1
    fi

    printf '[RUN] Checking repeat setup behavior\n'
    if ! docker exec "$container" bash /tmp/setup-developer-shell.sh >"$output_log" 2>&1; then
        cat "$output_log"
        cleanup_target
        return 1
    fi
    if (( VERBOSE )); then
        cat "$output_log"
    else
        sed -n '/^========== FINAL RESULT ==========$/,$p' "$output_log"
    fi

    printf '[RUN] Checking Zsh configuration and interactive startup\n'
    if ! docker exec "$container" bash -s <<'CONTAINER_TEST'
set -Eeuo pipefail

zsh -n "$HOME/.zshrc"
test "$(grep -Fc '# >>> developer-shell managed block >>>' "$HOME/.zshrc")" -eq 1
test "$(grep -Fc '# <<< developer-shell managed block <<<' "$HOME/.zshrc")" -eq 1
test -s "$HOME/.config/developer-shell/aliases.zsh"

for command_name in eza lazygit lazydocker yazi ya; do
    command -v "$command_name" >/dev/null
done

zsh -ic 'echo startup-ok' >/tmp/zsh-startup.out 2>/tmp/zsh-startup.err
grep -Fxq startup-ok /tmp/zsh-startup.out
test ! -s /tmp/zsh-startup.err

script -qec 'zsh -i -c "bindkey \"^R\""' /dev/null >/tmp/zsh-tty.out
grep -Fq history-incremental-search-backward /tmp/zsh-tty.out
CONTAINER_TEST
then
    echo "Functional checks failed for $target." >&2
    cleanup_target
    return 1
fi

cleanup_target
printf '[PASS] %s\n' "$target"
}

for target_spec in "${targets[@]}"; do
    IFS='|' read -r target image family package_manager dockerfile <<<"$target_spec"
    if [[ -n "$TARGET_FILTER" && "$target" != "$TARGET_FILTER" ]]; then
        continue
    fi
    if ! run_target "$target" "$image" "$family" "$package_manager" "$dockerfile"; then
        failed=1
        printf '[FAIL] %s\n' "$target" >&2
    fi
done

if (( failed )); then
    exit 1
fi

if [[ -n "$TARGET_FILTER" ]]; then
    printf 'Test completed: %s passed.\n' "$TARGET_FILTER"
else
    echo "Matrix completed: all targets passed."
fi
