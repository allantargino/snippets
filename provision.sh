#!/bin/bash

set -e

RG=aks-rg
AKS=aks
LOCATION=eastus2
NAMESPACE=ingress-basic

# AKS
az group create -n $RG -l $LOCATION
az aks create -n $AKS -g $RG
az aks get-credentials -n $AKS -g $RG

# HELM
kubectl create serviceaccount tiller --namespace=kube-system
kubectl create clusterrolebinding tiller-admin --serviceaccount=kube-system:tiller --clusterrole=cluster-admin
helm init --service-account=tiller

JSONPATH='{range .items[*]}{@.metadata.name}:{range @.status.conditions[*]}{@.type}={@.status};{end}{end}'; until kubectl get pods -l app=helm -n kube-system -o jsonpath="$JSONPATH" 2>&1 | grep -q "Ready=True"; do sleep 1; done


# INGRESS CONTROLLER
INGRESS_CONTROLLER_NAME=nginx
kubectl create namespace $NAMESPACE
helm install stable/nginx-ingress --namespace $NAMESPACE -n $INGRESS_CONTROLLER_NAME --set controller.replicaCount=2

# SAMPLE APPLICATION
helm repo add azure-samples https://azure-samples.github.io/helm-charts/
helm repo update
helm install azure-samples/aks-helloworld --namespace $NAMESPACE
helm install azure-samples/aks-helloworld \
    --namespace $NAMESPACE \
    --set title="AKS Ingress Demo" \
    --set serviceName="ingress-demo"

# INGRESS
kubectl apply -f hello-world-ingress.yaml -n $NAMESPACE

# WAIT FOR LB
external_ip=""; while [ -z $external_ip ]; do echo "Waiting for end point..."; external_ip=$(kubectl get svc $INGRESS_CONTROLLER_NAME-nginx-ingress-controller -n $NAMESPACE --template="{{range .status.loadBalancer.ingress}}{{.ip}}{{end}}"); [ -z "$external_ip" ] && sleep 10; done; echo "End point ready-" && echo $external_ip; export endpoint=$external_ip

# WAIT FOR APPS
JSONPATH='{range .items[*]}{@.metadata.name}:{range @.status.conditions[*]}{@.type}={@.status};{end}{end}'; until kubectl get pods -n $NAMESPACE -o jsonpath="$JSONPATH" 2>&1 | grep -q "Ready=True"; do sleep 1; done

echo '==> CALLING '$endpoint'/'
curl -s -I $endpoint/

echo '==> CALLING '$endpoint'/hello-world-two'
curl -s -I $endpoint/hello-world-two

echo SUCCESS.
