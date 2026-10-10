
FROM rockylinux:9

RUN dnf -y install \
    sudo \
    git \
    ca-certificates \
    shadow-utils \
    which \
    findutils \
    util-linux \
    procps-ng \
    hostname \
    && dnf clean all

RUN useradd -m -s /bin/bash developer \
    && echo "developer ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/developer \
    && chmod 0440 /etc/sudoers.d/developer

USER developer
WORKDIR /home/developer

CMD ["/bin/bash"]
