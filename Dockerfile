FROM jenkins/jenkins:2.528

# Switch to root for installing plugins and additional tools
USER root

# Copy the plugins file and install plugins
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt --verbose

# Install dependencies required for Ansible and Terraform
RUN apt-get update && apt-get install -y --no-install-recommends \
    ansible \
    curl \
    unzip \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install Terraform from HashiCorp release archives for the active architecture
ARG TERRAFORM_VERSION=1.7.5
# TARGETARCH is automatically populated by BuildKit when building multi-platform
# images. Fallback to dpkg when building without BuildKit or on a single
# architecture.
ARG TARGETARCH
RUN set -eux; \
    detected_arch="${TARGETARCH:-$(dpkg --print-architecture)}"; \
    case "$detected_arch" in \
      amd64|x86_64) terraform_arch="amd64" ;; \
      arm64|aarch64) terraform_arch="arm64" ;; \
      *) echo "Unsupported architecture: $detected_arch" >&2; exit 1 ;; \
    esac; \
    terraform_file="terraform_${TERRAFORM_VERSION}_linux_${terraform_arch}.zip"; \
    terraform_url="https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/${terraform_file}"; \
    terraform_zip="/tmp/${terraform_file}"; \
    curl -fsSLo "$terraform_zip" "$terraform_url"; \
    curl -fsSLo /tmp/terraform_SHA256SUMS "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_SHA256SUMS"; \
    grep "  ${terraform_file}" /tmp/terraform_SHA256SUMS > /tmp/terraform_SHA256SUMS_filtered; \
    (cd /tmp && sha256sum -c terraform_SHA256SUMS_filtered); \
    unzip "$terraform_zip" -d /usr/local/bin; \
    rm "$terraform_zip" /tmp/terraform_SHA256SUMS /tmp/terraform_SHA256SUMS_filtered; \
    terraform --version

# Switch back to the jenkins user
USER jenkins
