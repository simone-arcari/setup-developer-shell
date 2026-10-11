FROM debian:11-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN sed -i \
        -e 's|deb.debian.org/debian-security|archive.debian.org/debian-security|g' \
        -e 's|deb.debian.org/debian|archive.debian.org/debian|g' \
        /etc/apt/sources.list \
    && printf 'Acquire::Check-Valid-Until "false";\n' \
        > /etc/apt/apt.conf.d/99archive \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        sudo \
        git \
        ca-certificates \
        passwd \
        findutils \
        util-linux \
        procps \
        hostname \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash developer \
    && echo "developer ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/developer \
    && chmod 0440 /etc/sudoers.d/developer

USER developer
WORKDIR /home/developer

CMD ["/bin/bash"]
