FROM nvidia/cuda:12.6.2-cudnn-devel-ubuntu24.04

# Avoid prompts from apt
ENV DEBIAN_FRONTEND=noninteractive

# Install ssh, curl, wget and other basics
RUN apt-get update && apt-get install -y \
    openssh-server \
    curl \
    wget \
    sudo \
    ca-certificates \
    gnupg \
    lsb-release \
    unzip \
    build-essential \
    pkg-config \
    libssl-dev \
    git \
    python3 \
    python3-pip \
    vim-nox \
    tmux \
    lsof \
    iproute2 \
    gh \
    && rm -rf /var/lib/apt/lists/*

# Install Docker
RUN mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null && \
    apt-get update && \
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin && \
    rm -rf /var/lib/apt/lists/*

# Install GitHub CLI
RUN mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | gpg --dearmor -o /etc/apt/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null && \
    apt-get update && \
    apt-get install -y gh && \
    rm -rf /var/lib/apt/lists/*

# Install Node.js
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

# Add ubuntu user to docker group
RUN usermod -aG docker ubuntu || true

# Configure SSH
RUN mkdir /var/run/sshd

# Set password for 'ubuntu' user, ensure it has sudo access and set UID/GID to 1002
RUN if id "ubuntu" >/dev/null 2>&1; then \
        groupmod -g 1002 ubuntu && \
        usermod -u 1002 -g 1002 ubuntu && \
        echo "ubuntu:ubuntu" | chpasswd && \
        adduser ubuntu sudo; \
    else \
        groupadd -g 1002 ubuntu && \
        useradd -m -u 1002 -g 1002 -s /bin/bash ubuntu && \
        echo "ubuntu:ubuntu" | chpasswd && \
        adduser ubuntu sudo; \
    fi

# Install Rust for ubuntu user
USER ubuntu
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/home/ubuntu/.cargo/bin:${PATH}"

RUN rustup component add rustfmt

# Install Bun for ubuntu user
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/home/ubuntu/.bun/bin:${PATH}"

# Configure npm for user ubuntu
USER ubuntu
RUN mkdir /home/ubuntu/.npm-global && \
    npm config set prefix '/home/ubuntu/.npm-global'
ENV PATH="/home/ubuntu/.npm-global/bin:${PATH}"

# Install gemini-cli for ubuntu user using npm
RUN npm install -g @google/gemini-cli

# Install uv for ubuntu user
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/home/ubuntu/.local/bin:${PATH}"

# Install Flutter for ubuntu user
RUN git clone https://github.com/flutter/flutter.git /home/ubuntu/flutter -b stable
ENV PATH="/home/ubuntu/flutter/bin:${PATH}"
RUN flutter config --no-analytics && flutter precache

RUN curl -fsSL https://gh.io/copilot-install | bash
RUN printf '%s\n' \
    'set -g default-terminal "screen-256color"' \
    'set -gq utf8 on' \
    'set -gq status-utf8 on' \
    > /home/ubuntu/.tmux.conf \
    && mkdir -p /home/ubuntu/.copilot /home/ubuntu/.cache/copilot /home/ubuntu/.config/gh /home/ubuntu/.local

# Add paths to bashrc
RUN echo 'export PATH="/home/ubuntu/.npm-global/bin:/home/ubuntu/flutter/bin:/home/ubuntu/.cargo/bin:/home/ubuntu/.bun/bin:/home/ubuntu/.local/bin:${PATH}"' >> /home/ubuntu/.bashrc && \
    echo "alias gemini='gemini'" >> /home/ubuntu/.bashrc

# Ensure .gemini and .config/gh directories exist with correct permissions
RUN mkdir -p /home/ubuntu/.gemini /home/ubuntu/.config/gh && \
    chown ubuntu:ubuntu /home/ubuntu/.gemini /home/ubuntu/.config/gh && \
    chmod 700 /home/ubuntu/.gemini /home/ubuntu/.config/gh

USER root
# Configure passwordless sudo for the ubuntu user
RUN echo "ubuntu ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/ubuntu && \
    chmod 0440 /etc/sudoers.d/ubuntu

# Setup SSH key for ubuntu user
RUN mkdir -p /home/ubuntu/.ssh && \
    echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMG+LmtXe42CmQTL/dC4mUSQA1lLp7TskNuQZjFDrKDw ichikawa@honeymoon" > /home/ubuntu/.ssh/authorized_keys && \
    chown -R ubuntu:ubuntu /home/ubuntu/.ssh && \
    chmod 700 /home/ubuntu/.ssh && \
    chmod 600 /home/ubuntu/.ssh/authorized_keys

# Set root password for SSH access
RUN echo 'root:root' | chpasswd
# Allow root login via SSH
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config

# SSH login fix
RUN sed 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' -i /etc/pam.d/sshd

ENV NOTVISIBLE "in users profile"
RUN echo "export VISIBLE=now" >> /etc/profile

EXPOSE 22
CMD ["/usr/sbin/sshd", "-D"]
