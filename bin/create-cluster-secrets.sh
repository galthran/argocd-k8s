#!/bin/bash

if [[ $# -ne 1 ]]; then
  echo -e "\nMissing arguments!\n"
  echo -e "\nUssage $0 KEYVAULT_NAME\n\n"
  exit 1
fi

AAD_APPLICATION_NAME=microk8s

source "$(dirname "$0")/setup-env.sh"

KEYVAULT_NAME=$1

AAD_APPLICATION_ID=$(az ad sp list --display-name "${AAD_APPLICATION_NAME}" --query "[0].appId" -o tsv)
if [[ -z "${AAD_APPLICATION_ID}" ]]; then
  echo "Service principal '${AAD_APPLICATION_NAME}' not found" >&2
  exit 1
fi
echo "SERVICE_PRINCIPAL: ${AAD_APPLICATION_NAME} (appId: ${AAD_APPLICATION_ID})"

# Reset app password
APP_PASSWORD=$(az ad app credential reset --id ${AAD_APPLICATION_ID} --query password | tr -d \")
if [[ -z "${APP_PASSWORD}" ]]; then
  echo "Service principal '${APP_PASSWORD}' not found" >&2
  exit 1
fi
echo "APP_PASSWORD: ${APP_PASSWORD}"

# Create a Secret es-service-principal-secret containing the credentials for the Azure App Registration created above
kubectl delete secret es-service-principal-secret -n external-secrets
kubectl create secret generic es-service-principal-secret -n external-secrets --from-literal=client-id=${AAD_APPLICATION_ID} --from-literal=client-secret=${APP_PASSWORD}

az keyvault secret set --name microk8s-client-secret --vault-name ${KEYVAULT_NAME} --value ${APP_PASSWORD}