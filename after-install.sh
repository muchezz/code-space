#!/bin/bash

# Install Go
GO_LANG_VERSION=1.19
curl -L -o go.tar.gz "https://go.dev/dl/go${GO_LANG_VERSION}.linux-amd64.tar.gz" && \
    sudo tar -C /usr/local/ -xzf go.tar.gz && \
    echo "export PATH=$PATH:/usr/local/go/bin" tee ~/.zshrc ~/.bashrc

# Install Helm
HELM_VERSION="3.9.3"
curl -L -o helm.tar.gz "https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz" && \
    sudo tar -xzvf helm.tar.gz && \
    sudo mv linux-amd64/helm /usr/local/bin/

