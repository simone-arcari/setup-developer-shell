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

if ! command -v docker >/dev/null 2>&1; then
    echo "Docker non è disponibile nel PATH." >&2
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    echo "Il daemon Docker non è raggiungibile." >&2
    exit 1
fi

targets=(
    "el8|developer-el8-test|el|dnf"
    "el9|developer-el9-test|el|dnf"
    "el10|developer-el10-test|el|dnf"
    "debian|developer-debian-test|debian|apt-get"
    "ubuntu|developer-ubuntu-test|debian|apt-get"
)
failed=0

run_target() {
    local target="$1"
    local image="$2"
    local family="$3"
    local package_manager="$4"
    local container="setup-matrix-${target}-$$"
    local output_log

    output_log="$(mktemp)"
    printf '\n========== %s (%s) ==========\n' "$target" "$image"

    if (( BUILD_IMAGES )); then
        docker build -f "${ROOT_DIR}/test/${target}/Dockerfile" -t "$image" "$ROOT_DIR"
    fi

    docker run -d \
        --name "$container" \
        -v "${ROOT_DIR}/setup-terminal.sh:/tmp/setup-terminal.sh:ro" \
        "$image" bash -c 'sleep infinity' >/dev/null

    if ! docker exec "$container" bash /tmp/setup-terminal.sh >"$output_log" 2>&1; then
        cat "$output_log"
        docker rm -f "$container" >/dev/null 2>&1 || true
        rm -f "$output_log"
        return 1
    fi
    cat "$output_log"
    if ! grep -Fq "Famiglia: ${family}; package manager: ${package_manager}" "$output_log"; then
        echo "Rilevamento piattaforma inatteso per $target." >&2
        docker rm -f "$container" >/dev/null 2>&1 || true
        rm -f "$output_log"
        return 1
    fi

    if ! docker exec "$container" bash /tmp/setup-terminal.sh >"$output_log" 2>&1; then
        cat "$output_log"
        docker rm -f "$container" >/dev/null 2>&1 || true
        rm -f "$output_log"
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
        docker rm -f "$container" >/dev/null 2>&1 || true
        rm -f "$output_log"
        return 1
    fi

    docker rm -f "$container" >/dev/null
    rm -f "$output_log"
    printf '[PASS] %s\n' "$target"
}

for target_spec in "${targets[@]}"; do
    IFS='|' read -r target image family package_manager <<<"$target_spec"
    if ! run_target "$target" "$image" "$family" "$package_manager"; then
        failed=1
        printf '[FAIL] %s\n' "$target" >&2
    fi
done

if (( failed )); then
    exit 1
fi

echo "Matrice completata: tutti i target sono passati."
