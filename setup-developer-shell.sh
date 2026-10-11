
#!/usr/bin/env bash
set -uo pipefail

# Developer Shell Bootstrap - Rocky Linux / EL 9
# Optional tools are enabled by default.
# Disable them with: INSTALL_OPTIONAL_TOOLS=0
# Powerlevel10k: INSTALL_POWERLEVEL10K=1 (default)

OK=()
SKIPPED=()
WARNINGS=()
FAILURES=()

log()  { printf '\n==> %s\n' "$*"; }
info() { printf '[INFO] %s\n' "$*"; }
ok()   { OK+=("$*"); printf '[OK] %s\n' "$*"; }
skip() { SKIPPED+=("$*"); printf '[SKIP] %s\n' "$*"; }
warn() { WARNINGS+=("$*"); printf '[WARN] %s\n' "$*" >&2; }
fail() { FAILURES+=("$*"); printf '[FAIL] %s\n' "$*" >&2; }


dnf_repo_is_enabled() {
    local repo_id="$1"
    local repo_list

    if ! repo_list="$(sudo dnf -q repolist --enabled 2>&1)"; then
        warn "Impossibile verificare lo stato dei repository DNF."
        return 2
    fi

    awk -v target="$repo_id" '$1 == target { found=1 } END { exit !found }' \
        <<< "$repo_list"
}

ensure_dnf_config_manager() {
    if command -v rpm >/dev/null 2>&1 &&
       rpm -q dnf-plugins-core >/dev/null 2>&1; then
        return 0
    fi

    if sudo dnf -y install dnf-plugins-core; then
        return 0
    fi

    warn "Impossibile installare dnf-plugins-core."
    return 1
}

setup_el9_extra_repositories() {
    local epel_release_available=0

    # Do not change repository configuration outside Rocky/AlmaLinux 9.
    if [[ "${ID:-}" != "rocky" && "${ID:-}" != "almalinux" ]]; then
        skip "Configurazione automatica EPEL/CRB non applicabile a ${ID:-sconosciuto}"
        return 0
    fi

    if [[ "${VERSION_ID%%.*}" != "9" ]]; then
        skip "Configurazione automatica EPEL/CRB prevista solo per EL9"
        return 0
    fi

    info "Verifica dei repository EPEL e CRB..."

    if ! command -v rpm >/dev/null 2>&1; then
        warn "rpm non disponibile: impossibile verificare epel-release."
    elif ! rpm -q epel-release >/dev/null 2>&1; then
        if sudo dnf -y install epel-release; then
            ok "Repository EPEL installato."
            epel_release_available=1
        else
            warn "Impossibile installare epel-release."
        fi
    else
        skip "epel-release già installato"
        epel_release_available=1
    fi

    if ((epel_release_available)); then
        if dnf_repo_is_enabled epel; then
            skip "Repository EPEL già abilitato"
        else
            local repo_check_status=$?
            if ((repo_check_status == 1)); then
                if ensure_dnf_config_manager; then
                    if sudo dnf config-manager --set-enabled epel; then
                        ok "Repository EPEL abilitato."
                    else
                        warn "Impossibile abilitare il repository EPEL."
                    fi
                fi
            else
                warn "EPEL non modificato perché non è stato possibile verificarne lo stato."
            fi
        fi
    fi

    if dnf_repo_is_enabled crb; then
        skip "Repository CRB già abilitato"
        return 0
    else
        local repo_check_status=$?
        if ((repo_check_status != 1)); then
            warn "CRB non modificato perché non è stato possibile verificarne lo stato."
            return 0
        fi
    fi

    if command -v crb >/dev/null 2>&1; then
        if sudo crb enable; then
            ok "Repository CRB abilitato."
        else
            warn "Impossibile abilitare CRB tramite crb."
        fi
    else
        if ensure_dnf_config_manager; then
            if sudo dnf config-manager --set-enabled crb; then
                ok "Repository CRB abilitato tramite config-manager."
            else
                warn "Impossibile abilitare CRB tramite config-manager."
            fi
        fi
    fi

    return 0
}

optional_tool_command() {
    case "$1" in
        fzf) command -v fzf ;;
        bat) command -v bat || command -v batcat ;;
        ripgrep) command -v rg ;;
        btop) command -v btop ;;
        neovim) command -v nvim ;;
        zoxide) command -v zoxide ;;
        eza) command -v eza ;;
        lazygit) command -v lazygit ;;
        lazydocker) command -v lazydocker ;;
        git-delta) command -v delta ;;
        micro) command -v micro ;;
        yazi) command -v yazi ;;
        *) return 2 ;;
    esac
}

optional_package_name() {
    local tool="$1"

    case "$PLATFORM_FAMILY:$tool" in
        el:*)
            printf '%s\n' "$tool"
            ;;
        debian:git-delta)
            printf '%s\n' git-delta
            ;;
        debian:*)
            printf '%s\n' "$tool"
            ;;
        *)
            return 1
            ;;
    esac
}

optional_package_is_installed() {
    local package="$1"

    case "$PACKAGE_MANAGER" in
        dnf)
            rpm -q "$package" >/dev/null 2>&1
            ;;
        apt-get)
            dpkg-query -W -f='${Status}' "$package" 2>/dev/null |
                grep -q 'install ok installed'
            ;;
        *)
            return 2
            ;;
    esac
}

install_optional_package() {
    local package="$1"

    case "$PACKAGE_MANAGER" in
        dnf)
            sudo dnf -y install "$package"
            ;;
        apt-get)
            sudo env DEBIAN_FRONTEND=noninteractive \
                apt-get install -y --no-install-recommends "$package"
            ;;
        *)
            return 2
            ;;
    esac
}

install_optional_fallback() {
    case "$1" in
        eza) install_eza_release ;;
        yazi) install_yazi_release ;;
        lazygit) install_lazygit_release ;;
        lazydocker) install_lazydocker_release ;;
        *) return 1 ;;
    esac
}

install_eza_release() {
    local architecture
    local archive_name
    local expected_sha256
    local archive_url
    local install_dir="${HOME}/.local/bin"
    local install_path="${install_dir}/eza"
    local temp_dir

    case "$(uname -m)" in
        aarch64|arm64)
            architecture="aarch64"
            expected_sha256="40b87ae8628aa2ff0f0d2dc24ab52f689631366385c3da630bae745671fd71ec"
            ;;
        x86_64|amd64)
            architecture="x86_64"
            expected_sha256="35c70c5c43c29108075e58b893234c67ef585f0b53a7eaf8e9e7d4eec9f339b4"
            ;;
        *)
            warn "Eza non installato: architettura non supportata ($(uname -m))."
            return 1
            ;;
    esac

    if ! mkdir -p "$install_dir"; then
        warn "Eza non installato: impossibile creare $install_dir."
        return 1
    fi

    if [[ -e "$install_path" ]]; then
        warn "Eza non installato: il percorso esiste già ma non è utilizzabile: $install_path"
        return 1
    fi

    if ! command -v sha256sum >/dev/null 2>&1; then
        warn "Eza non installato: sha256sum non è disponibile per verificare l'archivio."
        return 1
    fi

    archive_name="eza_${architecture}-unknown-linux-gnu.tar.gz"
    archive_url="https://github.com/eza-community/eza/releases/download/v0.23.5/${archive_name}"
    temp_dir="$(mktemp -d "${install_dir}/.eza-install.XXXXXX")" || {
        warn "Eza non installato: impossibile creare una directory temporanea."
        return 1
    }

    if ! curl -fsSL "$archive_url" -o "${temp_dir}/${archive_name}"; then
        rm -rf "$temp_dir"
        warn "Download della release ufficiale Eza v0.23.5 non riuscito."
        return 1
    fi

    if ! printf '%s  %s\n' "$expected_sha256" "${temp_dir}/${archive_name}" |
        sha256sum --check --status; then
        rm -rf "$temp_dir"
        warn "Verifica SHA-256 della release Eza v0.23.5 non riuscita."
        return 1
    fi

    if ! tar -xzf "${temp_dir}/${archive_name}" \
        -C "$temp_dir" --strip-components=1 ./eza; then
        rm -rf "$temp_dir"
        warn "Estrazione del binario Eza non riuscita."
        return 1
    fi

    if ! chmod 0755 "${temp_dir}/eza" ||
       ! "${temp_dir}/eza" --version >/dev/null 2>&1; then
        rm -rf "$temp_dir"
        warn "Il binario Eza scaricato non supera la verifica di esecuzione."
        return 1
    fi

    if ! mv "${temp_dir}/eza" "$install_path"; then
        rm -rf "$temp_dir"
        warn "Installazione del binario Eza in $install_path non riuscita."
        return 1
    fi

    rm -rf "$temp_dir"
    ok "Eza v0.23.5 installato da release ufficiale verificata in $install_path"
}

install_lazygit_release() {
    local architecture
    local archive_name
    local expected_sha256
    local archive_url
    local install_dir="${HOME}/.local/bin"
    local install_path="${install_dir}/lazygit"
    local temp_dir

    case "$(uname -m)" in
        aarch64|arm64)
            architecture="arm64"
            expected_sha256="9a4fc4656897ac9f7877b835473ce1a75620cc267f554c57fc4ff266407f3257"
            ;;
        x86_64|amd64)
            architecture="x86_64"
            expected_sha256="5b45541155d20bd32bf2cc5ab5b7e3d91c2eebf0fb1242281350edc27d59d2b7"
            ;;
        *)
            warn "lazygit non installato: architettura non supportata ($(uname -m))."
            return 1
            ;;
    esac

    if ! mkdir -p "$install_dir"; then
        warn "lazygit non installato: impossibile creare $install_dir."
        return 1
    fi

    if [[ -e "$install_path" ]]; then
        warn "lazygit non installato: il percorso esiste già ma non è utilizzabile: $install_path"
        return 1
    fi

    if ! command -v sha256sum >/dev/null 2>&1; then
        warn "lazygit non installato: sha256sum non è disponibile per verificare l'archivio."
        return 1
    fi

    archive_name="lazygit_0.66.0_linux_${architecture}.tar.gz"
    archive_url="https://github.com/jesseduffield/lazygit/releases/download/v0.66.0/${archive_name}"
    temp_dir="$(mktemp -d "${install_dir}/.lazygit-install.XXXXXX")" || {
        warn "lazygit non installato: impossibile creare una directory temporanea."
        return 1
    }

    if ! curl -fsSL "$archive_url" -o "${temp_dir}/${archive_name}"; then
        rm -rf "$temp_dir"
        warn "Download della release ufficiale lazygit v0.66.0 non riuscito."
        return 1
    fi

    if ! printf '%s  %s\n' "$expected_sha256" "${temp_dir}/${archive_name}" |
        sha256sum --check --status; then
        rm -rf "$temp_dir"
        warn "Verifica SHA-256 della release lazygit v0.66.0 non riuscita."
        return 1
    fi

    if ! tar -xzf "${temp_dir}/${archive_name}" \
        -C "$temp_dir" --no-same-owner lazygit; then
        rm -rf "$temp_dir"
        warn "Estrazione del binario lazygit non riuscita."
        return 1
    fi

    if ! chmod 0755 "${temp_dir}/lazygit" ||
       ! "${temp_dir}/lazygit" --version >/dev/null 2>&1; then
        rm -rf "$temp_dir"
        warn "Il binario lazygit scaricato non supera la verifica di esecuzione."
        return 1
    fi

    if ! mv "${temp_dir}/lazygit" "$install_path"; then
        rm -rf "$temp_dir"
        warn "Installazione del binario lazygit in $install_path non riuscita."
        return 1
    fi

    rm -rf "$temp_dir"
    ok "lazygit v0.66.0 installato da release ufficiale verificata in $install_path"
}

install_lazydocker_release() {
    local architecture
    local archive_name
    local expected_sha256
    local archive_url
    local install_dir="${HOME}/.local/bin"
    local install_path="${install_dir}/lazydocker"
    local temp_dir

    case "$(uname -m)" in
        aarch64|arm64)
            architecture="arm64"
            expected_sha256="005c38b685aaa557e7d646d83a3dadb5024340eeed8c6a2e1949eee6f530de23"
            ;;
        x86_64|amd64)
            architecture="x86_64"
            expected_sha256="0d9dbfc26068b218e7ed84b104748cadc6e3cf733c0afd35465306fb39b9523c"
            ;;
        *)
            warn "lazydocker non installato: architettura non supportata ($(uname -m))."
            return 1
            ;;
    esac

    if ! mkdir -p "$install_dir"; then
        warn "lazydocker non installato: impossibile creare $install_dir."
        return 1
    fi

    if [[ -e "$install_path" ]]; then
        warn "lazydocker non installato: il percorso esiste già ma non è utilizzabile: $install_path"
        return 1
    fi

    if ! command -v sha256sum >/dev/null 2>&1; then
        warn "lazydocker non installato: sha256sum non è disponibile per verificare l'archivio."
        return 1
    fi

    archive_name="lazydocker_0.25.2_Linux_${architecture}.tar.gz"
    archive_url="https://github.com/jesseduffield/lazydocker/releases/download/v0.25.2/${archive_name}"
    temp_dir="$(mktemp -d "${install_dir}/.lazydocker-install.XXXXXX")" || {
        warn "lazydocker non installato: impossibile creare una directory temporanea."
        return 1
    }

    if ! curl -fsSL "$archive_url" -o "${temp_dir}/${archive_name}"; then
        rm -rf "$temp_dir"
        warn "Download della release ufficiale lazydocker v0.25.2 non riuscito."
        return 1
    fi

    if ! printf '%s  %s\n' "$expected_sha256" "${temp_dir}/${archive_name}" |
        sha256sum --check --status; then
        rm -rf "$temp_dir"
        warn "Verifica SHA-256 della release lazydocker v0.25.2 non riuscita."
        return 1
    fi

    if ! tar -xzf "${temp_dir}/${archive_name}" \
        -C "$temp_dir" --no-same-owner lazydocker; then
        rm -rf "$temp_dir"
        warn "Estrazione del binario lazydocker non riuscita."
        return 1
    fi

    if ! chmod 0755 "${temp_dir}/lazydocker" ||
       ! "${temp_dir}/lazydocker" --version >/dev/null 2>&1; then
        rm -rf "$temp_dir"
        warn "Il binario lazydocker scaricato non supera la verifica di esecuzione."
        return 1
    fi

    if ! mv "${temp_dir}/lazydocker" "$install_path"; then
        rm -rf "$temp_dir"
        warn "Installazione del binario lazydocker in $install_path non riuscita."
        return 1
    fi

    rm -rf "$temp_dir"
    ok "lazydocker v0.25.2 installato da release ufficiale verificata in $install_path"
}

install_yazi_release() {
    local architecture
    local archive_name
    local archive_root
    local expected_sha256
    local archive_url
    local install_dir="${HOME}/.local/bin"
    local yazi_path="${install_dir}/yazi"
    local ya_path="${install_dir}/ya"
    local temp_dir

    case "$(uname -m)" in
        aarch64|arm64)
            architecture="aarch64"
            expected_sha256="dd569daecaae914185f295634109295ccd25c1b42b02eb89a74f651970024f2e"
            ;;
        x86_64|amd64)
            architecture="x86_64"
            expected_sha256="9b9c39decccf8cb0ff53a7d637d38f8a79d93bbd0099f4ea9c619ef6bb392f5d"
            ;;
        *)
            warn "Yazi non installato: architettura non supportata ($(uname -m))."
            return 1
            ;;
    esac

    if ! mkdir -p "$install_dir"; then
        warn "Yazi non installato: impossibile creare $install_dir."
        return 1
    fi

    if [[ -e "$yazi_path" || -e "$ya_path" ]]; then
        warn "Yazi non installato: yazi o ya esiste già in $install_dir ma non è disponibile nel PATH."
        return 1
    fi

    if ! command -v sha256sum >/dev/null 2>&1 ||
       ! command -v unzip >/dev/null 2>&1; then
        warn "Yazi non installato: sha256sum e unzip sono necessari per verificare ed estrarre l'archivio."
        return 1
    fi

    archive_name="yazi-${architecture}-unknown-linux-musl.zip"
    archive_root="yazi-${architecture}-unknown-linux-musl"
    archive_url="https://github.com/sxyazi/yazi/releases/download/v26.9.1/${archive_name}"
    temp_dir="$(mktemp -d "${install_dir}/.yazi-install.XXXXXX")" || {
        warn "Yazi non installato: impossibile creare una directory temporanea."
        return 1
    }

    if ! curl -fsSL "$archive_url" -o "${temp_dir}/${archive_name}"; then
        rm -rf "$temp_dir"
        warn "Download della release ufficiale Yazi v26.9.1 (musl) non riuscito."
        return 1
    fi

    if ! printf '%s  %s\n' "$expected_sha256" "${temp_dir}/${archive_name}" |
        sha256sum --check --status; then
        rm -rf "$temp_dir"
        warn "Verifica SHA-256 della release Yazi v26.9.1 (musl) non riuscita."
        return 1
    fi

    if ! unzip -p "${temp_dir}/${archive_name}" "${archive_root}/yazi" \
        > "${temp_dir}/yazi" ||
       ! unzip -p "${temp_dir}/${archive_name}" "${archive_root}/ya" \
        > "${temp_dir}/ya"; then
        rm -rf "$temp_dir"
        warn "Estrazione dei binari Yazi non riuscita."
        return 1
    fi

    if ! chmod 0755 "${temp_dir}/yazi" "${temp_dir}/ya" ||
       ! "${temp_dir}/yazi" --version >/dev/null 2>&1 ||
       ! "${temp_dir}/ya" --version >/dev/null 2>&1; then
        rm -rf "$temp_dir"
        warn "I binari Yazi scaricati non superano la verifica di esecuzione."
        return 1
    fi

    if ! mv "${temp_dir}/yazi" "$yazi_path"; then
        rm -rf "$temp_dir"
        warn "Installazione del binario Yazi in $yazi_path non riuscita."
        return 1
    fi
    if ! mv "${temp_dir}/ya" "$ya_path"; then
        rm -f "$yazi_path"
        rm -rf "$temp_dir"
        warn "Installazione del binario ya in $ya_path non riuscita."
        return 1
    fi

    rm -rf "$temp_dir"
    ok "Yazi v26.9.1 installato da release ufficiale verificata in $install_dir"
}

INSTALL_OPTIONAL_TOOLS="${INSTALL_OPTIONAL_TOOLS:-1}"
INSTALL_POWERLEVEL10K="${INSTALL_POWERLEVEL10K:-1}"

PLATFORM_ID=""
PLATFORM_VERSION=""
PLATFORM_FAMILY=""
PACKAGE_MANAGER=""
PLATFORM_DISPLAY=""

detect_platform() {
    if [[ ! -r /etc/os-release ]]; then
        echo "Impossibile leggere /etc/os-release." >&2
        return 1
    fi

    # shellcheck disable=SC1091
    . /etc/os-release

    PLATFORM_ID="${ID:-}"
    PLATFORM_VERSION="${VERSION_ID:-}"
    PLATFORM_DISPLAY="${PRETTY_NAME:-${PLATFORM_ID:-sconosciuto} ${PLATFORM_VERSION:-}}"

    case "$PLATFORM_ID" in
        rocky|almalinux|rhel)
            PLATFORM_FAMILY="el"
            PACKAGE_MANAGER="dnf"
            ;;
        debian|ubuntu)
            PLATFORM_FAMILY="debian"
            PACKAGE_MANAGER="apt-get"
            ;;
        *)
            echo "Distribuzione non riconosciuta: ${PLATFORM_ID:-sconosciuto}." >&2
            return 1
            ;;
    esac

    if ! command -v "$PACKAGE_MANAGER" >/dev/null 2>&1; then
        echo "Piattaforma rilevata: $PLATFORM_DISPLAY ($PLATFORM_FAMILY), ma $PACKAGE_MANAGER non è disponibile nel PATH." >&2
        return 1
    fi

    info "Piattaforma rilevata: $PLATFORM_DISPLAY"
    info "Famiglia: $PLATFORM_FAMILY; package manager: $PACKAGE_MANAGER"

    case "$PLATFORM_FAMILY:$PLATFORM_ID:$PLATFORM_VERSION" in
        el:rocky:8*|el:rocky:9*|el:rocky:10*|\
        el:almalinux:8*|el:almalinux:9*|el:almalinux:10*|\
        el:rhel:8*|el:rhel:9*|el:rhel:10*|\
        debian:debian:10*|debian:debian:11*|debian:debian:12*|\
        debian:debian:13*|\
        debian:ubuntu:22.04*|debian:ubuntu:24.04*|debian:ubuntu:26.04*)
            return 0
            ;;
        *)
            echo "Versione di piattaforma riconosciuta ma non supportata: $PLATFORM_DISPLAY." >&2
            return 1
            ;;
    esac
}

install_system_packages() {
    case "$PACKAGE_MANAGER" in
        dnf)
            sudo dnf -y install "$@"
            ;;
        apt-get)
            sudo apt-get update &&
                sudo env DEBIAN_FRONTEND=noninteractive \
                    apt-get install -y --no-install-recommends "$@"
            ;;
        *)
            echo "Package manager non supportato: $PACKAGE_MANAGER." >&2
            return 1
            ;;
    esac
}

if [[ $EUID -eq 0 ]]; then
    echo "Esegui lo script come utente normale, non come root." >&2
    exit 1
fi

if ! detect_platform; then
    exit 1
fi

if ! command -v sudo >/dev/null 2>&1; then
    echo "sudo non è installato o non è disponibile nel PATH." >&2
    exit 1
fi

if ! sudo -v; then
    echo "Impossibile ottenere i privilegi sudo." >&2
    exit 1
fi

if [[ -z "${HOME:-}" || ! -d "$HOME" || ! -w "$HOME" ]]; then
    echo "HOME non è impostata su una directory esistente e scrivibile." >&2
    exit 1
fi

export PATH="${HOME}/.local/bin:${PATH}"

ZSH_DIR="${HOME}/.oh-my-zsh"
ZSH_CUSTOM_DIR="${ZSH_CUSTOM:-${ZSH_DIR}/custom}"
PLUGIN_DIR="${ZSH_CUSTOM_DIR}/plugins"
THEME_DIR="${ZSH_CUSTOM_DIR}/themes"
CONFIG_DIR="${HOME}/.config/developer-shell"
ALIAS_FILE="${CONFIG_DIR}/aliases.zsh"
ZSHRC="${HOME}/.zshrc"

# ------------------------------------------------------------
# 1. Essential system utilities
# curl-minimal is accepted on EL; package names are mapped by platform.
# ------------------------------------------------------------

log "Installazione dei pacchetti essenziali"

case "$PLATFORM_FAMILY" in
    el)
        BASE_PACKAGES=(
            zsh git ca-certificates iproute procps-ng util-linux findutils
            diffutils which hostname tar gzip unzip
        )
        ;;
    debian)
        BASE_PACKAGES=(
            zsh git ca-certificates iproute2 procps util-linux findutils
            diffutils hostname tar gzip unzip
        )
        ;;
esac

if ! command -v curl >/dev/null 2>&1; then
    if [[ "$PLATFORM_FAMILY" == "el" ]]; then
        for curl_package in curl curl-minimal; do
            if rpm -q "$curl_package" >/dev/null 2>&1; then
                echo "Il pacchetto $curl_package è installato ma il comando curl non è nel PATH; correggere il sistema prima di continuare." >&2
                exit 1
            fi
        done
        BASE_PACKAGES+=(curl-minimal)
    else
        if dpkg-query -W -f='${Status}' curl 2>/dev/null | grep -q 'install ok installed'; then
            echo "Il pacchetto curl risulta installato ma il comando non è nel PATH; correggere il sistema prima di continuare." >&2
            exit 1
        fi
        BASE_PACKAGES+=(curl)
    fi
fi

if install_system_packages "${BASE_PACKAGES[@]}"; then
    ok "Pacchetti essenziali installati"
else
    fail "Installazione dei pacchetti essenziali"
    exit 1
fi

for cmd in zsh git curl; do
    if command -v "$cmd" >/dev/null 2>&1; then
        ok "Comando disponibile: $cmd"
    else
        fail "Comando necessario non disponibile: $cmd"
        exit 1
    fi
done

clone_pinned_if_missing() {
    local url="$1"
    local dest="$2"
    local label="$3"
    local ref="$4"
    local expected_commit="$5"
    local parent_dir
    local temp_dir
    local staged_repo
    local actual_commit

    if [[ -d "$dest/.git" ]]; then
        skip "$label già presente; revisione esistente preservata"
        return 0
    fi

    if [[ -e "$dest" ]]; then
        warn "$label: destinazione esistente ma non è un repository Git"
        return 1
    fi

    parent_dir="$(dirname "$dest")"
    mkdir -p "$parent_dir" || {
        warn "$label: impossibile creare la directory di destinazione"
        return 1
    }

    temp_dir="$(mktemp -d "${parent_dir}/.${label}.clone.XXXXXX")" || {
        warn "$label: impossibile creare una directory temporanea"
        return 1
    }
    staged_repo="${temp_dir}/repository"

    if ! git clone --depth 1 --single-branch --branch "$ref" \
        "$url" "$staged_repo"; then
        rm -rf "$temp_dir"
        warn "Clone di $label ($ref) non riuscito"
        return 1
    fi

    actual_commit="$(git -C "$staged_repo" rev-parse HEAD)" || {
        rm -rf "$temp_dir"
        warn "Impossibile verificare la revisione di $label"
        return 1
    }

    if [[ "$actual_commit" != "$expected_commit" ]] &&
       git -C "$staged_repo" fetch --depth 1 origin "$expected_commit" &&
       git -C "$staged_repo" checkout --detach FETCH_HEAD; then
        actual_commit="$(git -C "$staged_repo" rev-parse HEAD)" || {
            rm -rf "$temp_dir"
            warn "Impossibile verificare la revisione di $label"
            return 1
        }
    fi

    if [[ "$actual_commit" != "$expected_commit" ]]; then
        rm -rf "$temp_dir"
        warn "Revisione inattesa per $label: attesa $expected_commit, ricevuta $actual_commit"
        return 1
    fi

    if ! mv "$staged_repo" "$dest"; then
        rm -rf "$temp_dir"
        warn "Installazione atomica di $label non riuscita"
        return 1
    fi
    rmdir "$temp_dir" || warn "Pulizia della directory temporanea di $label non riuscita"

    ok "$label installato alla revisione $expected_commit"
}

# ------------------------------------------------------------
# 2. Oh My Zsh
# ------------------------------------------------------------

log "Installazione di Oh My Zsh"

clone_pinned_if_missing \
    https://github.com/ohmyzsh/ohmyzsh.git \
    "$ZSH_DIR" \
    "Oh-My-Zsh" \
    master \
    42a4ccb1b14dbeffe81259105a5243b4f4cb618e || {
        fail "Installazione di Oh My Zsh"
        exit 1
    }

if [[ ! -d "$ZSH_DIR" ]]; then
    fail "Directory Oh My Zsh non trovata"
    exit 1
fi

mkdir -p "$PLUGIN_DIR" "$THEME_DIR" "$CONFIG_DIR" || {
    fail "Creazione delle directory di configurazione"
    exit 1
}

# ------------------------------------------------------------
# 3. Zsh plugins and theme
# ------------------------------------------------------------

log "Installazione dei plugin Zsh"

clone_pinned_if_missing \
    https://github.com/zsh-users/zsh-autosuggestions.git \
    "$PLUGIN_DIR/zsh-autosuggestions" \
    "zsh-autosuggestions" \
    v0.7.1 \
    e52ee8ca55bcc56a17c828767a3f98f22a68d4eb || true

clone_pinned_if_missing \
    https://github.com/zsh-users/zsh-syntax-highlighting.git \
    "$PLUGIN_DIR/zsh-syntax-highlighting" \
    "zsh-syntax-highlighting" \
    0.8.0 \
    db085e4661f6aafd24e5acb5b2e17e4dd5dddf3e || true

clone_pinned_if_missing \
    https://github.com/zsh-users/zsh-completions.git \
    "$PLUGIN_DIR/zsh-completions" \
    "zsh-completions" \
    0.9.0 \
    53dd086f56f4d947be3a4b97c57f6c1f8a61900d || true

if [[ "$INSTALL_POWERLEVEL10K" == "1" ]]; then
    log "Installazione di Powerlevel10k"

    clone_pinned_if_missing \
        https://github.com/romkatv/powerlevel10k.git \
        "$THEME_DIR/powerlevel10k" \
        "Powerlevel10k" \
        v1.20.0 \
        35833ea15f14b71dbcebc7e54c104d8d56ca5268 || true
else
    skip "Powerlevel10k disabilitato"
fi

# ------------------------------------------------------------
# 4. Optional developer CLI tools
# ------------------------------------------------------------

if [[ "$INSTALL_OPTIONAL_TOOLS" == "1" ]]; then
    if [[ "$PLATFORM_FAMILY" == "el" &&
          "${PLATFORM_VERSION%%.*}" == "9" ]]; then
        setup_el9_extra_repositories
    elif [[ "$PACKAGE_MANAGER" == "apt-get" ]]; then
        log "Aggiornamento degli indici APT per gli strumenti opzionali"
        if sudo apt-get update; then
            ok "Indici APT aggiornati"
        else
            warn "Aggiornamento degli indici APT non riuscito; i pacchetti opzionali potrebbero non essere disponibili."
        fi
    fi

    log "Installazione degli strumenti opzionali"

    OPTIONAL_TOOLS=(
        fzf
        bat
        ripgrep
        btop
        neovim
        zoxide
        eza
        lazygit
        lazydocker
        git-delta
        micro
        yazi
    )

    for tool in "${OPTIONAL_TOOLS[@]}"; do
        package="$(optional_package_name "$tool")" || {
            warn "Nessuna mappatura del pacchetto $tool per $PLATFORM_FAMILY."
            continue
        }

        if optional_tool_command "$tool" >/dev/null 2>&1; then
            skip "Comando già disponibile per $tool"
            continue
        fi

        if optional_package_is_installed "$package"; then
            warn "Pacchetto $package risulta installato, ma il comando $tool non è disponibile."
            continue
        fi

        if install_optional_package "$package"; then
            if optional_tool_command "$tool" >/dev/null 2>&1; then
                ok "Strumento opzionale disponibile: $tool ($package)"
            else
                warn "Pacchetto $package installato, ma il comando $tool non è disponibile."
                if install_optional_fallback "$tool"; then
                    ok "Strumento opzionale disponibile tramite release verificata: $tool"
                fi
            fi
        elif install_optional_fallback "$tool"; then
            ok "Strumento opzionale disponibile tramite release ufficiale verificata: $tool"
        else
            warn "Strumento $tool non disponibile: pacchetto $package assente o installazione fallita via $PACKAGE_MANAGER; fallback ufficiale applicato quando previsto."
        fi
    done
else
    if [[ "$INSTALL_OPTIONAL_TOOLS" != "1" ]]; then
        skip "Strumenti opzionali disabilitati"
    fi
fi

# ------------------------------------------------------------
# 5. Useful aliases
# ------------------------------------------------------------

log "Configurazione degli alias"

TMP_ALIASES="$(mktemp "${CONFIG_DIR}/aliases.zsh.tmp.XXXXXX")" || {
    fail "Creazione del file temporaneo degli alias"
    exit 1
}

if ! cat > "$TMP_ALIASES" <<'ALIASES'
# General navigation
if command -v eza >/dev/null 2>&1; then
    alias ls='eza --color=auto'
    alias ll='eza -al --color=auto'
    alias la='eza -a --color=auto'
    alias l='eza -l --color=auto'
    alias tree='eza --tree --icons'
else
    alias ll='ls -alF'
    alias la='ls -A'
    alias l='ls -CF'
fi
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias c='clear'

# System information
alias dfh='df -h'
alias duh='du -sh'
alias freeh='free -h'
alias ports='ss -tulpn'
alias myip='curl -fsS https://api.ipify.org; printf "\n"'

# Safer defaults
alias grep='grep --color=auto'
alias cp='cp -i'
alias mv='mv -i'
alias rm='rm -i'

# Optional tools: define convenience aliases only when useful
if command -v bat >/dev/null 2>&1; then
    alias cat='bat'
elif command -v batcat >/dev/null 2>&1; then
    alias cat='batcat'
fi

if command -v rg >/dev/null 2>&1; then
    alias rgi='rg -i'
fi

if command -v nvim >/dev/null 2>&1; then
    alias vim='nvim'
fi
ALIASES

then
    rm -f "$TMP_ALIASES"
    fail "Scrittura del file temporaneo degli alias non riuscita"
    exit 1
fi

if [[ -f "$ALIAS_FILE" ]] && cmp -s "$TMP_ALIASES" "$ALIAS_FILE"; then
    rm -f "$TMP_ALIASES"
    skip "Alias già aggiornati"
else
    if [[ -e "$ALIAS_FILE" && ! -f "$ALIAS_FILE" ]]; then
        rm -f "$TMP_ALIASES"
        fail "Il percorso degli alias esiste ma non è un file regolare: $ALIAS_FILE"
        exit 1
    fi

    if [[ -f "$ALIAS_FILE" ]]; then
        ALIAS_BACKUP="$(mktemp "${ALIAS_FILE}.bak.$(date +%Y%m%d%H%M%S).XXXXXX")" || {
            rm -f "$TMP_ALIASES"
            fail "Creazione del backup degli alias"
            exit 1
        }
        if ! cp -p "$ALIAS_FILE" "$ALIAS_BACKUP"; then
            rm -f "$TMP_ALIASES" "$ALIAS_BACKUP"
            fail "Backup degli alias non riuscito"
            exit 1
        fi
        chmod --reference="$ALIAS_FILE" "$TMP_ALIASES" || {
            rm -f "$TMP_ALIASES"
            fail "Ripristino dei permessi degli alias"
            exit 1
        }
    fi

    if mv -f "$TMP_ALIASES" "$ALIAS_FILE"; then
        ok "Alias salvati in $ALIAS_FILE"
    else
        rm -f "$TMP_ALIASES"
        fail "Aggiornamento atomico degli alias non riuscito"
        exit 1
    fi
fi

# ------------------------------------------------------------
# 6. Configure .zshrc without deleting user customizations
# ------------------------------------------------------------

log "Configurazione di .zshrc"

if [[ -f "$ZSHRC" ]]; then
    :
elif [[ -e "$ZSHRC" ]]; then
    fail ".zshrc esiste ma non è un file regolare"
    exit 1
else
    touch "$ZSHRC" || {
        fail "Impossibile creare .zshrc"
        exit 1
    }
fi

BEGIN_MARKER="# >>> developer-shell managed block >>>"
END_MARKER="# <<< developer-shell managed block <<<"

TMP_ZSHRC_CONFIG="$(mktemp "${HOME}/.zshrc.config.XXXXXX")" || {
    fail "Creazione del file temporaneo per .zshrc"
    exit 1
}
TMP_ZSHRC="$(mktemp "${HOME}/.zshrc.tmp.XXXXXX")" || {
    rm -f "$TMP_ZSHRC_CONFIG"
    fail "Creazione del file temporaneo finale di .zshrc"
    exit 1
}

if ! cat > "$TMP_ZSHRC_CONFIG" <<'ZSHCONFIG'
# >>> developer-shell managed block >>>

export ZSH="${HOME}/.oh-my-zsh"
export ZSH_CUSTOM="${ZSH}/custom"
export PATH="${HOME}/.local/bin:${PATH}"

# Extra completions must be on fpath before Oh My Zsh loads.
if [[ -d "${ZSH_CUSTOM}/plugins/zsh-completions/src" ]]; then
    fpath=("${ZSH_CUSTOM}/plugins/zsh-completions/src" "${fpath[@]}")
fi

plugins=(git)

[[ -d "${ZSH_CUSTOM}/plugins/zsh-autosuggestions" ]] &&
    plugins+=(zsh-autosuggestions)

[[ -d "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting" ]] &&
    plugins+=(zsh-syntax-highlighting)

if [[ -d "${ZSH_CUSTOM}/themes/powerlevel10k" ]]; then
    ZSH_THEME="powerlevel10k/powerlevel10k"
else
    ZSH_THEME="robbyrussell"
fi

source "${ZSH}/oh-my-zsh.sh"

[[ -f "${HOME}/.config/developer-shell/aliases.zsh" ]] &&
    source "${HOME}/.config/developer-shell/aliases.zsh"

if [[ -o interactive && -t 0 && -t 1 ]]; then
    if command -v zoxide >/dev/null 2>&1; then
        eval "$(zoxide init zsh)"
    fi

    if command -v fzf >/dev/null 2>&1; then
        for fzf_key_bindings in \
            /usr/share/fzf/shell/key-bindings.zsh \
            /usr/share/doc/fzf/shell/key-bindings.zsh \
            /usr/share/doc/fzf/examples/key-bindings.zsh; do
            if [[ -r "$fzf_key_bindings" ]]; then
                source "$fzf_key_bindings"
                break
            fi
        done
    fi
fi

# <<< developer-shell managed block <<<
ZSHCONFIG
then
    rm -f "$TMP_ZSHRC_CONFIG" "$TMP_ZSHRC"
    fail "Scrittura della configurazione temporanea di .zshrc non riuscita"
    exit 1
fi

if ! awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" \
    -v config_file="$TMP_ZSHRC_CONFIG" '
    $0 == begin {
        if (inside || ++begins > 1) {
            invalid=1
            next
        }
        inside=1
        while ((getline config_line < config_file) > 0) print config_line
        close(config_file)
        next
    }
    $0 == end {
        if (!inside || ++ends > 1) {
            invalid=1
            next
        }
        inside=0
        next
    }
    !inside { print }
    END {
        if (inside || begins != ends || begins > 1 || ends > 1) invalid=1
        exit invalid
    }
' "$ZSHRC" > "$TMP_ZSHRC"; then
    rm -f "$TMP_ZSHRC_CONFIG" "$TMP_ZSHRC"
    fail "Marcatori del blocco gestito in .zshrc mancanti o malformati; file originale lasciato invariato"
    exit 1
fi

if ! grep -Fq "$BEGIN_MARKER" "$ZSHRC"; then
    if [[ -s "$TMP_ZSHRC" ]]; then
        printf '\n' >> "$TMP_ZSHRC" || {
            rm -f "$TMP_ZSHRC_CONFIG" "$TMP_ZSHRC"
            fail "Preparazione della nuova configurazione .zshrc"
            exit 1
        }
    fi
    cat "$TMP_ZSHRC_CONFIG" >> "$TMP_ZSHRC" || {
        rm -f "$TMP_ZSHRC_CONFIG" "$TMP_ZSHRC"
        fail "Preparazione della nuova configurazione .zshrc"
        exit 1
    }
fi
rm -f "$TMP_ZSHRC_CONFIG"

if ! zsh -n "$TMP_ZSHRC"; then
    rm -f "$TMP_ZSHRC"
    fail "Errore di sintassi nella configurazione proposta di .zshrc"
    exit 1
fi

if cmp -s "$TMP_ZSHRC" "$ZSHRC"; then
    rm -f "$TMP_ZSHRC"
    skip ".zshrc già aggiornato"
else
    ZSHRC_BACKUP="$(mktemp "${ZSHRC}.bak.$(date +%Y%m%d%H%M%S).XXXXXX")" || {
        rm -f "$TMP_ZSHRC"
        fail "Creazione del backup di .zshrc"
        exit 1
    }
    if ! cp -p "$ZSHRC" "$ZSHRC_BACKUP"; then
        rm -f "$TMP_ZSHRC" "$ZSHRC_BACKUP"
        fail "Backup di .zshrc non riuscito"
        exit 1
    fi
    chmod --reference="$ZSHRC" "$TMP_ZSHRC" || {
        rm -f "$TMP_ZSHRC"
        fail "Ripristino dei permessi di .zshrc"
        exit 1
    }
    if mv -f "$TMP_ZSHRC" "$ZSHRC"; then
        ok ".zshrc aggiornato atomicamente"
    else
        rm -f "$TMP_ZSHRC"
        fail "Aggiornamento atomico di .zshrc non riuscito"
        exit 1
    fi
fi

if zsh -n "$ZSHRC"; then
    ok ".zshrc aggiornato e sintassi valida"
else
    fail "Errore di sintassi in .zshrc"
fi

# ------------------------------------------------------------
# 7. Default shell: best effort (often unavailable in containers)
# ------------------------------------------------------------

log "Configurazione della shell predefinita"

ZSH_PATH="$(command -v zsh)"
CURRENT_USER="$(id -un)" || {
    warn "Impossibile determinare l'utente corrente; cambio shell saltato."
    CURRENT_USER=""
}
REGISTERED_ZSH_PATH=""
ZSH_REAL_PATH="$(readlink -f "$ZSH_PATH" 2>/dev/null)" || ZSH_REAL_PATH=""

if [[ ! -x "$ZSH_PATH" ]]; then
    warn "Il percorso di Zsh non è eseguibile; cambio shell saltato."
elif [[ -n "$ZSH_REAL_PATH" && -r /etc/shells ]]; then
    while IFS= read -r shell_candidate; do
        [[ -x "$shell_candidate" ]] || continue
        candidate_real_path="$(readlink -f "$shell_candidate" 2>/dev/null)" || continue
        if [[ "$candidate_real_path" == "$ZSH_REAL_PATH" ]]; then
            REGISTERED_ZSH_PATH="$shell_candidate"
            break
        fi
    done < /etc/shells
fi

if [[ -z "$CURRENT_USER" ]]; then
    skip "Utente non identificato; cambia la shell predefinita manualmente"
elif [[ -z "$REGISTERED_ZSH_PATH" ]]; then
    skip "Zsh non è registrato in /etc/shells; shell predefinita invariata"
elif command -v chsh >/dev/null 2>&1; then
    CURRENT_LOGIN_SHELL="$(getent passwd "$CURRENT_USER" | awk -F: 'NR == 1 { print $7 }')"
    if [[ "$CURRENT_LOGIN_SHELL" == "$REGISTERED_ZSH_PATH" ]]; then
        skip "Zsh è già la shell predefinita per $CURRENT_USER"
    elif sudo chsh -s "$REGISTERED_ZSH_PATH" "$CURRENT_USER"; then
        ok "Shell predefinita impostata su Zsh"
    else
        warn "Impossibile impostare la shell predefinita di $CURRENT_USER; avvia Zsh con: zsh"
    fi
else
    skip "chsh non disponibile; avvia Zsh con: zsh"
fi

# ------------------------------------------------------------
# 8. Final command availability report
# ------------------------------------------------------------

log "Verifica dei comandi"

CHECK_COMMANDS=(
    zsh git curl ls grep df du ss free hostname
    fzf bat rg btop nvim zoxide eza lazygit lazydocker delta micro yazi
)

for cmd in "${CHECK_COMMANDS[@]}"; do
    if command -v "$cmd" >/dev/null 2>&1; then
        ok "Comando disponibile: $cmd"
    else
        skip "Comando non disponibile: $cmd"
    fi
done

printf '\n========== RISULTATO FINALE ==========\n'
printf 'Piattaforma: %s (%s, %s)\n' \
    "$PLATFORM_DISPLAY" "$PLATFORM_FAMILY" "$PACKAGE_MANAGER"
printf 'OK:       %d\n' "${#OK[@]}"
printf 'Saltati:  %d\n' "${#SKIPPED[@]}"
printf 'Avvisi:   %d\n' "${#WARNINGS[@]}"
printf 'Errori:   %d\n' "${#FAILURES[@]}"

if ((${#WARNINGS[@]})); then
    printf '\nAvvisi:\n'
    printf ' - %s\n' "${WARNINGS[@]}"
fi

if ((${#FAILURES[@]})); then
    printf '\nErrori:\n'
    printf ' - %s\n' "${FAILURES[@]}"
fi

printf '\nAvvia la shell configurata con: zsh\n'
printf 'Per disabilitare i tool opzionali: INSTALL_OPTIONAL_TOOLS=0 bash setup-developer-shell.sh\n'

((${#FAILURES[@]} == 0))
