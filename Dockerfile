FROM jenkins/jenkins:2.528

# Switch to root for installing plugins and additional tools
USER root

# TARGETARCH and TARGETVARIANT are automatically populated by BuildKit when
# building multi-platform images. Fallback to the runtime architecture and
# variant when building without BuildKit or on a single architecture.
ARG TARGETARCH
ARG TARGETVARIANT

# Default versions for HashiCorp tools installed when repository packages are
# unavailable for the target architecture.
ARG PACKER_VERSION=1.11.1
ARG TERRAFORM_VERSION=1.9.5

# Copy the plugins file and install plugins
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt --verbose

# Install common dependencies and tools aligned with the inbound agent image
RUN set -eux; \
    raw_arch="${TARGETARCH:-$(dpkg --print-architecture)}"; \
    variant="${TARGETVARIANT:-}"; \
    if { [ "$raw_arch" = "arm" ] || [ "$raw_arch" = "armhf" ] || [ "$raw_arch" = "armv7l" ]; } \
       && [ -n "$variant" ] && [ "$variant" != "v7" ]; then \
      echo "Unsupported ARM variant: $variant" >&2; exit 1; \
    fi; \
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
    case "$raw_arch" in \
      amd64|x86_64) \
        arch_packages="cpu-checker qemu-kvm qemu-system-x86" \
        ;; \
      arm64|aarch64) \
        arch_packages="qemu-system-arm" \
        ;; \
      arm|armhf|armv7l) \
        arch_packages="qemu-system-arm" \
        ;; \
      *) \
        echo "Unsupported architecture: $raw_arch" >&2; exit 1 \
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
      arm|armhf|armv7l) repo_arch="" ;; \
      *) echo "Unsupported architecture: $arch" >&2; exit 1 ;; \
    esac; \
    if [ -z "$repo_arch" ]; then \
      echo "Skipping HashiCorp repository setup for architecture $arch"; \
    else \
      mkdir -p /usr/share/keyrings; \
      curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg; \
      codename="$(. /etc/os-release && echo "$VERSION_CODENAME")"; \
      echo "deb [arch=${repo_arch} signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com ${codename} main" > /etc/apt/sources.list.d/hashicorp.list; \
    fi

# Install Terraform, Packer, and Ansible. For architectures where HashiCorp does
# not publish apt packages (e.g., armhf), download verified archives instead.
RUN set -eux; \
    arch="${TARGETARCH:-$(dpkg --print-architecture)}"; \
    case "$arch" in \
      amd64|x86_64) normalized_arch="amd64" ;; \
      arm64|aarch64) normalized_arch="arm64" ;; \
      arm|armhf|armv7l) normalized_arch="arm" ;; \
      *) echo "Unsupported architecture: $arch" >&2; exit 1 ;; \
    esac; \
    if [ "$normalized_arch" = "arm" ]; then \
      apt-get update; \
      apt-get install -y ansible; \
      apt-get clean; \
      rm -rf /var/lib/apt/lists/*; \
      for tool in terraform packer; do \
        case "$tool" in \
          terraform) version="$TERRAFORM_VERSION" ;; \
          packer) version="$PACKER_VERSION" ;; \
        esac; \
        tmp_dir="$(mktemp -d)"; \
        file="${tool}_${version}_linux_${normalized_arch}.zip"; \
        url="https://releases.hashicorp.com/${tool}/${version}/${file}"; \
        sums_url="https://releases.hashicorp.com/${tool}/${version}/${tool}_${version}_SHA256SUMS"; \
        curl -fsSLo "${tmp_dir}/${file}" "$url"; \
        curl -fsSLo "${tmp_dir}/SHA256SUMS" "$sums_url"; \
        grep "  ${file}" "${tmp_dir}/SHA256SUMS" > "${tmp_dir}/SHA256SUMS.filtered"; \
        (cd "$tmp_dir" && sha256sum -c "SHA256SUMS.filtered"); \
        unzip -o "${tmp_dir}/${file}" -d /usr/local/bin; \
        rm -rf "$tmp_dir"; \
      done; \
    else \
      apt-get update; \
      apt-get install -y terraform packer ansible; \
      apt-get clean; \
      rm -rf /var/lib/apt/lists/*; \
    fi

# Install MinIO Client
RUN set -eux; \
    arch="${TARGETARCH:-$(dpkg --print-architecture)}"; \
    case "$arch" in \
      amd64|x86_64) mc_arch="amd64" ;; \
      arm64|aarch64) mc_arch="arm64" ;; \
      arm|armhf|armv7l) mc_arch="arm" ;; \
      *) echo "Unsupported architecture: $arch" >&2; exit 1 ;; \
    esac; \
    curl -sSL "https://dl.min.io/client/mc/release/linux-${mc_arch}/mc" -o /usr/local/bin/mc; \
    chmod +x /usr/local/bin/mc

# Switch back to the jenkins user
USER jenkins
