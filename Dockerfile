FROM jenkins/jenkins:2.528

# Switch to root for installing plugins and additional tools
USER root

# TARGETARCH is automatically populated by BuildKit when building multi-platform
# images. Fallback to the runtime architecture when building without BuildKit or
# on a single architecture.
ARG TARGETARCH

# Copy the plugins file and install plugins
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt --verbose

# Install common dependencies and tools aligned with the inbound agent image
RUN set -eux; \
    arch="${TARGETARCH:-$(dpkg --print-architecture)}"; \
    export DEBIAN_FRONTEND=noninteractive; \
    apt-get update; \
    common_packages="apt-transport-https \
      curl \
      gnupg \
      lsb-release \
      software-properties-common \
      jq \
      python3 \
      python3-pip \
      bat \
      bridge-utils \
      btop \
      dnsutils \
      duf \
      ethtool \
      fd-find \
      gh \
      git \
      htop \
      ifupdown \
      iotop \
      iperf3 \
      iptables \
      libvirt-clients \
      libvirt-daemon-system \
      lshw \
      lsof \
      make \
      default-mysql-client \
      nano \
      net-tools \
      netcat-openbsd \
      neovim \
      nfs-common \
      nmap \
      open-iscsi \
      parted \
      postgresql-client \
      python3-venv \
      qemu-guest-agent \
      ripgrep \
      rsync \
      screen \
      smartmontools \
      strace \
      tcpdump \
      tmux \
      traceroute \
      tree \
      ufw \
      unzip \
      util-linux \
      vim \
      virtinst \
      wget \
      whois \
      xorriso \
      zip"; \
    arch_packages=""; \
    case "$arch" in \
      amd64|x86_64) \
        arch_packages="cpu-checker qemu-kvm qemu-system-x86" \
        ;; \
      arm64|aarch64) \
        arch_packages="qemu-system-arm" \
        ;; \
      *) \
        echo "Unsupported architecture: $arch" >&2; exit 1 \
        ;; \
    esac; \
    apt-get install -y --no-install-recommends $common_packages $arch_packages; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

# Install boto3 and botocore via pip, overriding system restrictions.
RUN pip3 install --break-system-packages boto3 botocore

# Add the HashiCorp repository (Terraform + Packer come from here)
RUN set -eux; \
    arch="${TARGETARCH:-$(dpkg --print-architecture)}"; \
    case "$arch" in \
      amd64|x86_64) repo_arch="amd64" ;; \
      arm64|aarch64) repo_arch="arm64" ;; \
      *) echo "Unsupported architecture: $arch" >&2; exit 1 ;; \
    esac; \
    mkdir -p /usr/share/keyrings; \
    curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg; \
    codename="$(. /etc/os-release && echo "$VERSION_CODENAME")"; \
    echo "deb [arch=${repo_arch} signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com ${codename} main" > /etc/apt/sources.list.d/hashicorp.list

# Install Terraform, Packer, and Ansible from the HashiCorp repository
RUN apt-get update && apt-get install -y \
    terraform \
    packer \
    ansible \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install MinIO Client
RUN set -eux; \
    arch="${TARGETARCH:-$(dpkg --print-architecture)}"; \
    case "$arch" in \
      amd64|x86_64) mc_arch="amd64" ;; \
      arm64|aarch64) mc_arch="arm64" ;; \
      *) echo "Unsupported architecture: $arch" >&2; exit 1 ;; \
    esac; \
    curl -sSL "https://dl.min.io/client/mc/release/linux-${mc_arch}/mc" -o /usr/local/bin/mc; \
    chmod +x /usr/local/bin/mc

# Switch back to the jenkins user
USER jenkins
