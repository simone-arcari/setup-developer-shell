#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_IMAGES=1

if [[ "${1:-}" == "--no-build" ]]; then
    BUILD_IMAGES=0
elif [[ -n "${1:-}" ]]; then
    printf 'Uso: %s [--no-build]\n' "$0" >&2
    exit 2
fi

for required_command in docker mktemp grep; do
    if ! command -v "$required_command" >/dev/null 2>&1; then
        printf 'Comando richiesto non disponibile: %s\n' "$required_command" >&2
        exit 1
    fi
done

if ! docker info >/dev/null 2>&1; then
    echo "Il daemon Docker non è raggiungibile." >&2
    exit 1
fi

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
failed=0

run_target() {
    local target="$1"
    local image="$2"
    local family="$3"
    local package_manager="$4"
    local dockerfile="$5"
    local container="setup-matrix-${target}-$$"
    local output_log
    local container_created=0

    output_log="$(mktemp)"
    printf '\n========== %s (%s) ==========\n' "$target" "$image"

    if (( BUILD_IMAGES )); then
        if ! docker build -f "${ROOT_DIR}/test/${dockerfile}/Dockerfile" -t "$image" "$ROOT_DIR"; then
            rm -f "$output_log"
            return 1
        fi
    fi

    if ! docker run -d \
        --name "$container" \
        -v "${ROOT_DIR}/setup-developer-shell.sh:/tmp/setup-developer-shell.sh:ro" \
        "$image" bash -c 'sleep infinity' >/dev/null; then
        rm -f "$output_log"
        return 1
    fi
    container_created=1

    cleanup_target() {
        if (( container_created )); then
            docker rm -f "$container" >/dev/null 2>&1 || true
            container_created=0
        fi
        rm -f "$output_log"
    }

    if ! docker exec "$container" bash /tmp/setup-developer-shell.sh >"$output_log" 2>&1; then
        cat "$output_log"
        cleanup_target
        return 1
    fi
    cat "$output_log"
    if ! grep -Fq "Famiglia: ${family}; package manager: ${package_manager}" "$output_log"; then
        echo "Rilevamento piattaforma inatteso per $target." >&2
        cleanup_target
        return 1
    fi

    if ! docker exec "$container" bash /tmp/setup-developer-shell.sh >"$output_log" 2>&1; then
        cat "$output_log"
        cleanup_target
        return 1
    fi
    cat "$output_log"

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
    echo "Verifiche funzionali fallite per $target." >&2
    cleanup_target
    return 1
fi

cleanup_target
printf '[PASS] %s\n' "$target"
}

for target_spec in "${targets[@]}"; do
    IFS='|' read -r target image family package_manager dockerfile <<<"$target_spec"
    if ! run_target "$target" "$image" "$family" "$package_manager" "$dockerfile"; then
        failed=1
        printf '[FAIL] %s\n' "$target" >&2
    fi
done

if (( failed )); then
    exit 1
fi

echo "Matrice completata: tutti i target sono passati."
