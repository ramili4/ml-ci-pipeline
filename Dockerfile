FROM jenkins/jenkins:lts

USER root

# Install required packages
RUN apt-get update && \
    apt-get install -y \
    wget \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install MinIO client (mc)
RUN curl -o /usr/local/bin/mc https://dl.min.io/client/mc/release/linux-amd64/mc && \
    chmod +x /usr/local/bin/mc

# Install Docker
RUN apt-get update && \
    apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release \
    && curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg \
    && echo \
      "deb [arch=$(dpkg --print-architecture signed-by=/usr/share/keyrings/docker-archive-keyring.gpg)] https://download.docker.com/linux/debian \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null \
    && apt-get update && \
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Add jenkins user to the docker group so it can run docker commands
RUN usermod -aG docker jenkins

# Switch back to jenkins user
USER jenkins

# Verify installation (Optional but recommended)
RUN docker run hello-world

# Create workspace directory (Optional but good practice)
WORKDIR /home/jenkins/agent

# Install kubectl (Optional, if needed)
#RUN curl -LO "https://dl.k8s.io/release/v1.27.3/bin/linux/amd64/kubectl" && \ # Replace with your version
#    chmod +x kubectl && \
#    mv kubectl /usr/local/bin/

# Install docker-compose (Optional, if needed - usually already included with docker install)
#RUN curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose && \
#    chmod +x /usr/local/bin/docker-compose
