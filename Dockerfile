FROM jenkins/jenkins:2.497

# Switch to root for installing plugins and additional tools
USER root

# Copy the plugins file and install plugins
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt --verbose

# Install prerequisite packages for adding repositories and downloading files
RUN apt-get update && apt-get install -y \
    apt-transport-https \
    curl \
    gnupg \
    lsb-release \
    software-properties-common

# Add HashiCorp's GPG key and repository (for Terraform)
RUN curl -fsSL https://apt.releases.hashicorp.com/gpg | apt-key add - && \
    echo "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main" > /etc/apt/sources.list.d/hashicorp.list

# Update package lists and install Terraform and Ansible
RUN apt-get update && apt-get install -y terraform ansible && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Switch back to the jenkins user
USER jenkins
