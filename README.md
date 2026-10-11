# Developer Shell Setup

`setup-terminal.sh` prepares a practical Zsh environment for day-to-day use on
your Linux machine. It installs the system packages it needs, configures
[Oh My Zsh](https://ohmyz.sh/) with useful plugins and the Powerlevel10k theme,
adds optional command-line tools, and writes a set of shell aliases. It is
designed to be run directly by a regular user on the machine you want to
configure, not as a Docker entrypoint.

## Supported platforms

The script recognizes and has been tested on:

- Enterprise Linux (EL) family: Rocky Linux 8, 9, and 10
- Debian 10, 11, 12, and 13
- Ubuntu 22.04, 24.04, and 26.04

Debian 10 and 11 are end-of-life legacy compatibility targets and are not
recommended for new installations. The EL package flow is also designed for
AlmaLinux and RHEL 8, 9, and 10, but those distributions are not included in
the test matrix. Here, EL means the Enterprise Linux family. Automatic
EPEL/CRB setup applies only to Rocky Linux and AlmaLinux 9; repository
configuration on RHEL is left to the administrator.

Optional package availability depends on the enabled repositories and
architecture. If an optional package is unavailable, the script reports a
warning; Eza, Yazi, lazygit, and lazydocker have pinned upstream release
fallbacks for aarch64/ARM64 and x86_64. Downloads are SHA-256 verified before
installation under `~/.local/bin`.

## Run on your machine

Requirements:

- A supported Linux distribution and Bash
- A regular user account with working `sudo` access
- Network access to the configured package repositories and GitHub

Review the script, then run it as your regular user from the repository:

```bash
bash setup-terminal.sh
```

Do not run it as root. The script asks `sudo` for permission when system
packages or supported EL9 repositories need to be changed.

Optional command-line tools are installed by default. To skip them:

```bash
INSTALL_OPTIONAL_TOOLS=0 bash setup-terminal.sh
```

Powerlevel10k is also enabled by default. To use Oh My Zsh without that theme:

```bash
INSTALL_POWERLEVEL10K=0 bash setup-terminal.sh
```

The script adds or updates a marked section in `~/.zshrc`, writes aliases to
`~/.config/developer-shell/aliases.zsh`, and backs up existing files before
changing them. It attempts to make Zsh your login shell when possible; if the
system does not allow that, start it with `zsh`. Read the final summary for
optional-tool warnings or steps that need attention.

The optional tools are fzf, bat, ripgrep, btop, Neovim, zoxide, Eza, lazygit,
lazydocker, git-delta, micro, and Yazi. Eza is the maintained successor to
exa. Yazi's fallback uses the upstream musl build; lazydocker also needs a
working Docker CLI and daemon to be useful.

Oh My Zsh, its plugins, Powerlevel10k, and the upstream binary fallbacks are
pinned to specific revisions or versions. Updating them requires reviewing
the corresponding references and checksums in `setup-terminal.sh`.

## Test across Linux platforms with Docker

Docker is only used here to test the setup script against disposable
environments; it is not required to run the script on your own machine. The
Dockerfiles under `test/` provide one test image per distribution version:

```text
test/
├── debian/
│   ├── 10/
│   ├── 11/
│   ├── 12/
│   └── 13/
├── el/
│   ├── 8/
│   ├── 9/
│   └── 10/
└── ubuntu/
    ├── 22.04/
    ├── 24.04/
    └── 26.04/
```

Debian 10 and 11 test images use Debian's archive repositories because those
releases are end-of-life. To build the images and run the setup/configuration
checks for every target from the repository root:

```bash
test/run-matrix.sh
```

The matrix runs the setup twice in each container, then checks platform
detection, Zsh configuration syntax, generated aliases, optional command
availability, interactive startup, and the fzf Ctrl-R binding in a TTY. It
removes its temporary containers when finished. Docker and a reachable Docker
daemon are required.

To reuse previously built `developer-*-test` images:

```bash
test/run-matrix.sh --no-build
```

To build one image manually, for example Ubuntu 24.04:

```bash
docker build -f test/ubuntu/24.04/Dockerfile -t developer-ubuntu .
```

The test images use the host's native architecture. The full matrix has passed
in Docker Desktop's ARM64 environment; this does not replace testing on native
x86_64 hardware or cover every host-specific policy, mirror, proxy, SELinux,
identity-management, or login-shell configuration.

## Before changing your machine

- Review the script before running it: it installs packages and updates shell
  configuration. With optional tools enabled, it can also configure EPEL and
  CRB on Rocky/AlmaLinux 9.
- Keep a separate backup of important files even though the script backs up
  files it changes.
- Try it first on a disposable machine or in a test environment matching your
  distribution and policies.
- Containers cannot validate host-specific login-shell behavior, security
  policy, or integration with tools and services already on your machine.
