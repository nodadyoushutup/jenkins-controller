FROM jenkins/jenkins:2.528

# Switch to root for installing plugins
USER root

# Copy the plugins file and install plugins
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt --verbose

# Switch back to the jenkins user
USER jenkins
