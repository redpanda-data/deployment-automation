FROM ubuntu:22.04
ARG DEBIAN_FRONTEND=noninteractive

ENV DA_AWS_ACCESS_KEY_ID="default"
ENV DA_AWS_SECRET_ACCESS_KEY="default"
ENV AWS_DEFAULT_REGION="default"

# Install the good stuff
RUN apt-get update \
    && apt install unzip -y \
    && apt install wget -y \
    && apt install curl -y \
    && apt install vim -y \
    && apt-get install -y git \
    && apt-get install -y software-properties-common \
    && apt-add-repository --yes --update ppa:ansible/ansible \
    && apt-get install -y ansible \
    && rm -rf /var/lib/apt/lists/*

# Install Terraform
RUN wget https://releases.hashicorp.com/terraform/1.3.7/terraform_1.3.7_linux_amd64.zip \
    && unzip terraform_1.3.7_linux_amd64.zip -d /usr/local/bin \
    && rm terraform_1.3.7_linux_amd64.zip

# Install task
RUN curl -sSLf "https://github.com/go-task/task/releases/download/v3.21.0/task_linux_amd64.tar.gz" | tar -xz -C /usr/local/bin

## uncomment for use as a local client
#RUN mkdir -p /app
#COPY . /app

# Set the default command to run when the container starts
CMD ["/bin/bash"]
