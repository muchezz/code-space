#!/bin/bash

# Install Azure CLI
curl -sL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/microsoft.gpg > /dev/null
AZ_REPO=$(lsb_release -cs) && echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ $AZ_REPO main" | sudo tee /etc/apt/sources.list.d/azure-cli.list
sudo apt update && sudo apt install -y azure-cli make gcc

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

# Install ClusterCTL
CLUSTERCTL_VERSION=1.2.1
curl -L -o clusterctl "https://github.com/kubernetes-sigs/cluster-api/releases/download/v${CLUSTERCTL_VERSION}/clusterctl-linux-amd64" && \
    chmod +x clusterctl && \
    sudo mv clusterctl /usr/local/bin/

# Set environment variables
export WORKDIR=$(pwd)
export LOCATION="eastus"
export SUFFIX=$RANDOM

export CAPI_MGMT_CLUSTER_RG_NAME="wasp-shadow-mgmt-$SUFFIX"
export CAPI_MGMT_CLUSTER_NAME="capi-mgmt-$SUFFIX"
export CAPZ_WORKER_CLUSTER_RG_NAME="wasp-shadow-work-$SUFFIX"
export CAPZ_WORKER_CLUSTER_CLUSTER_NAME="capz-work-$SUFFIX"

export SSH_KEY_PATH="$HOME/.ssh/id_rsa"

# Log in to Azure
az login --scope https://graph.microsoft.com//.default

# Create SSH key if it doesn't exist
if [[ ! -f "$SSH_KEY_PATH" ]]
then
    ssh-keygen -m PEM -b 4096 -t rsa -f "$SSH_KEY_PATH" -q -N "" 
fi

# Get Azure account info
az account show -o json > $WORKDIR/azure_account.json

# Create CAPI Management Cluster Resource Group
az group create \
    -g $CAPI_MGMT_CLUSTER_RG_NAME \
    -l $LOCATION

export AZURE_SUBSCRIPTION_ID=$(cat $WORKDIR/azure_account.json | jq -r .id)
export AZURE_TENANT_ID=$(cat $WORKDIR/azure_account.json | jq -r .tenantId)

# Create CAPI Service Principal
az ad sp create-for-rbac --name "${CAPI_MGMT_CLUSTER_NAME}-spn" --role contributor --scopes "/subscriptions/$AZURE_SUBSCRIPTION_ID" > $WORKDIR/azure_spn_info.json

export AZURE_CLIENT_ID=$(cat $WORKDIR/azure_spn_info.json | jq -r .appId)
export AZURE_CLIENT_SECRET=$(cat $WORKDIR/azure_spn_info.json | jq -r .password)

# Base64 encode the variables
export AZURE_SUBSCRIPTION_ID_B64="$(echo -n "$AZURE_SUBSCRIPTION_ID" | base64 | tr -d '\n')"
export AZURE_TENANT_ID_B64="$(echo -n "$AZURE_TENANT_ID" | base64 | tr -d '\n')"
export AZURE_CLIENT_ID_B64="$(echo -n "$AZURE_CLIENT_ID" | base64 | tr -d '\n')"
export AZURE_CLIENT_SECRET_B64="$(echo -n "$AZURE_CLIENT_SECRET" | base64 | tr -d '\n')"

# Clone the required repo with CAPZ bits
git clone https://github.com/devigned/cluster-api-provider-azure
cd cluster-api-provider-azure
git checkout --track origin/wasm-flavor

# Create env variables output script
echo '#! /bin/bash' > $WORKDIR/outputs.sh
echo "export AZURE_SUBSCRIPTION_ID=$AZURE_SUBSCRIPTION_ID" >> $WORKDIR/outputs.sh 
echo "export AZURE_TENANT_ID=$AZURE_TENANT_ID" >> $WORKDIR/outputs.sh
echo "export LOCATION=$LOCATION" >> $WORKDIR/outputs.sh
echo "export SUFFIX=$SUFFIX" >> $WORKDIR/outputs.sh
echo "export CAPI_MGMT_CLUSTER_RG_NAME=$CAPI_MGMT_CLUSTER_RG_NAME" >> $WORKDIR/outputs.sh
echo "export CAPI_MGMT_CLUSTER_NAME=$CAPI_MGMT_CLUSTER_NAME" >> $WORKDIR/outputs.sh
echo "export CAPZ_WORKER_CLUSTER_RG_NAME=$CAPZ_WORKER_CLUSTER_RG_NAME" >> $WORKDIR/outputs.sh
echo "export CAPZ_WORKER_CLUSTER_CLUSTER_NAME=$CAPZ_WORKER_CLUSTER_CLUSTER_NAME" >> $WORKDIR/outputs.sh
echo "export SSH_KEY_PATH=$SSH_KEY_PATH" >> $WORKDIR/outputs.sh

# Create a secret to include the password of the Service Principal identity created in Azure
kubectl create secret generic "${AZURE_CLUSTER_IDENTITY_SECRET_NAME}" --from-literal=clientSecret="${AZURE_CLIENT_SECRET}" --namespace "${AZURE_CLUSTER_IDENTITY_SECRET_NAMESPACE}"
