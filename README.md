# Developer terminal bootstrap for EL 9

`setup-terminal.sh` configures a Zsh developer environment on the tested
container targets Rocky Linux 8, 9, and 10; Debian 13; and Ubuntu 24.04. Its EL
package flow is also designed for AlmaLinux and RHEL 8, 9, and 10, but those
distributions are not yet covered by the container test matrix. Run it as a
regular user with working `sudo` access:

```bash
bash setup-terminal.sh
```

The script installs essential system packages, Oh My Zsh, Zsh plugins, and
Powerlevel10k. Optional command-line tools are enabled by default. To skip
those tools and the related automatic EPEL/CRB setup:

```bash
INSTALL_OPTIONAL_TOOLS=0 bash setup-terminal.sh
```

To skip Powerlevel10k:

```bash
INSTALL_POWERLEVEL10K=0 bash setup-terminal.sh
```

The script reports the detected distribution, platform family, and package
manager before making system changes. Essential and optional package names are
mapped for DNF and APT. Rocky/AlmaLinux 9 repository setup remains limited to
EPEL and CRB; other EL versions do not receive automatic repository changes.
Unavailable Eza, Yazi, lazygit, and lazydocker packages use their pinned,
checksum-verified upstream releases when supported by the target architecture.

Automatic EPEL and CRB configuration is limited to Rocky Linux 9 and AlmaLinux
9. RHEL is supported for the base shell setup, but repository configuration is
left to the system administrator. Optional package availability depends on the
target's enabled repositories; unavailable tools are reported as warnings.
The script does not add third-party repositories outside the explicitly
supported EL9 EPEL/CRB setup or install unverified binaries. If Eza is
unavailable from the package manager, the script downloads the pinned official
Eza v0.23.5 Linux release for aarch64/ARM64 or x86_64, verifies its SHA-256
digest, and installs it under `~/.local/bin`.

Eza is the maintained successor to exa; upstream marks exa as unmaintained.
When Eza is available, the generated Zsh aliases use it for `ls`, `ll`, `la`,
and `l`.

If the package manager cannot provide Yazi, the script downloads the pinned
official Yazi v26.9.1 Linux musl release for aarch64/ARM64 or x86_64, verifies
its SHA-256 digest, and installs both `yazi` and its companion `ya` under
`~/.local/bin`. The musl build avoids depending on a newer glibc than Rocky
Linux 9 provides.

If the package manager cannot provide lazygit, the script downloads the pinned
official lazygit v0.66.0 Linux release for aarch64/ARM64 or x86_64, verifies
its SHA-256 digest, and installs it under `~/.local/bin`.

If the package manager cannot provide lazydocker, the script downloads the
pinned official lazydocker v0.25.2 Linux release for aarch64/ARM64 or x86_64,
verifies its SHA-256 digest, and installs it under `~/.local/bin`. Running
lazydocker also requires a usable Docker CLI and daemon; the test image does
not include them.

The four release fallbacks have been exercised through the setup script on
Rocky Linux 8/9/10, Debian 13, and Ubuntu 24.04 using the host's ARM64 Docker
environment; each installed command was located in `PATH` and passed a
`--version` invocation. The x86_64 Eza, lazygit, lazydocker, Yazi, and `ya`
release assets were separately checksum-verified and launched on Rocky Linux
8 with glibc 2.28. These Docker/emulation checks do not replace tests on native
x86_64 hardware or every supported target distribution and architecture.

## Container testing

Test images are provided for Rocky Linux 8, 9, and 10, Debian 13, and Ubuntu
24.04. Build the image for the target platform from the repository root:

```bash
docker build -f test/el8/Dockerfile -t developer-el8 .
docker build -f test/el9/Dockerfile -t developer-el9 .
docker build -f test/el10/Dockerfile -t developer-el10 .
docker build -f test/debian/Dockerfile -t developer-debian .
docker build -f test/ubuntu/Dockerfile -t developer-ubuntu .
```

Start a persistent container (replace `developer-el9` with the image being
tested):

```bash
docker run -d --name el9-setup-test \
  -v "$PWD/setup-terminal.sh:/tmp/setup-terminal.sh:ro" \
  developer-el9 bash -c 'sleep infinity'
```

Run the script twice in that same container to check rerun behavior:

```bash
docker exec -it el9-setup-test bash /tmp/setup-terminal.sh
docker exec -it el9-setup-test bash /tmp/setup-terminal.sh
```

Remove the test container when finished:

```bash
docker rm -f el9-setup-test
```

The Dockerfile uses the host's native architecture. The tested image in this
project was `linux/arm64`; that verifies execution in Docker Desktop's ARM64
environment, not on every ARM server or hardware model. An emulated
`--platform linux/amd64` test is useful for compatibility checks but does not
replace testing on a real x86_64 target.

The container uses a passwordless-sudo test user. This does not validate
interactive sudo policies, host security controls, or changes to a real user's
login shell. The image does not install the Docker CLI or daemon: Docker aliases
in the generated Zsh configuration are conveniences only and do not imply
Docker is present or usable.

## Before using on a real machine

- Review the script before running it. It installs system packages and, on
  Rocky/AlmaLinux 9 when optional tools are enabled, may install EPEL and enable
  CRB using `sudo`.
- The script updates its marked block in `~/.zshrc`, writes
  `~/.config/developer-shell/aliases.zsh`, and backs up files before changing
  them. Keep a separate backup of important configuration.
- Oh My Zsh, its plugins, and Powerlevel10k are cloned at pinned Git revisions.
  Updating them requires reviewing and changing both the requested ref and the
  expected commit in `setup-terminal.sh`.
- Test on a disposable system matching the target distribution and policy
  before broad rollout. Container tests do not cover host-specific SELinux,
  proxy, repository mirror, identity-management, or login-shell policies.
- A successful script exit means the required setup completed; optional-tool
  warnings and an unavailable `chsh` may still be reported. Read the final
  summary before considering a machine fully configured.
