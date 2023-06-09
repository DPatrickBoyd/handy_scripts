#!/bin/bash

# You need to have bash/*nix, jq and kubectl installed for this script to work. I currently use WSL with an http_proxy set to acces my clusters

echo "This script will create a file that will contain sensitive information, please take care not to commit or share it with anyone!"
echo -e

# Prompt for cluster name
read -p "Enter cluster name: " CLUSTER_NAME

# Set current context to cluster name
kubectl config use-context $CLUSTER_NAME
CLUSTER=$CLUSTER_NAME

# Prompt for namespace
read -p "Enter namespace: " NAMESPACE

# Save namespace to variable
MY_NAMESPACE=$NAMESPACE


DEPLOYMENT_LIST=$(kubectl get deployment -o name |  sed 's/deployment\.apps\///')
# Set the name of the file, delete it if it exists already
if [ -f "allpodinfo_$CLUSTER.txt" ]; then
    echo "File exists. Deleting..."
    rm "allpodinfo_$CLUSTER.txt"
    echo "File deleted."
fi

#feel free to take out these next 3 lines if there are no global configMaps that aren't assigned to a deployment directly which will be set under the pods json output spec.containers.env.name.valueFrom, where the other is set from spec.containers.envFrom
echo "Global configMap:" >> allpodinfo_$CLUSTER.txt
kubectl get configmap cloud-global-config -o json -n $MY_NAMESPACE | jq '.data | to_entries | map("\(.key)=\(.value|tostring)") | .[]' -r >> allpodinfo_$CLUSTER.txt
echo -e "\n" >> allpodinfo_$CLUSTER.txt

#loop through all deployments, grab pod env vars, configMaps and secrets
for NAME in $DEPLOYMENT_LIST
do
    echo "______________________________________________________________________"
    # get the name of first pod of the deployment
    POD_NAME=$(kubectl get pod -n $MY_NAMESPACE  -l app=$NAME -o jsonpath="{.items[0].metadata.name}")
    echo "Getting information for $NAME by peeking at $POD_NAME"
    echo $NAME >> allpodinfo_$CLUSTER.txt
    # Get the ConfigMap and Secret associated with the pod
    if [ -n "$POD_NAME" ]; then
    CONFIG_MAP=$(kubectl describe pod $POD_NAME -n $MY_NAMESPACE | grep -A1 "Environment Variables from:" | awk '/ConfigMap/ {print $1}' | sed 's/^[ \t]*//')
    SECRET=$(kubectl describe pod $POD_NAME -n cloud| grep -A2 "Environment Variables from:" | awk '/Secret/ {print $1}' | sed 's/^[ \t]*//')
    fi
    kubectl get pod $POD_NAME -o json -n $MY_NAMESPACE | jq '.spec.containers[].env[] | if .valueFrom.configMapKeyRef then "\(.name)=See global configMap value \(.valueFrom.configMapKeyRef.key)" elif .valueFrom.fieldRef then "\(.name)=\(.valueFrom.fieldRef.apiVersion):\(.valueFrom.fieldRef.fieldPath)"  else "\(.name)=\(.value|tostring)" end' -r >> allpodinfo_$CLUSTER.txt

    # If there is a ConfigMap associated with the pod, expand its variables
    if [ ! -z "$CONFIG_MAP" ]; then
    echo "Expanding variables in ConfigMap $CONFIG_MAP"
    kubectl get configmap $CONFIG_MAP -o json -n $MY_NAMESPACE | jq '.data | to_entries | map("\(.key)=\(.value|tostring)") | .[]' -r >> allpodinfo_$CLUSTER.txt
    fi

    # If there is a Secret associated with the pod, expand its variables
    if [ ! -z "$SECRET" ]; then
    echo "Expanding variables in Secret $SECRET"
    kubectl get secret "$SECRET" -o json -n $MY_NAMESPACE | jq '.data | to_entries | map("\(.key)=\(.value|@base64d|tostring | gsub(",|\"|\\\""; ""))") | .[]' -r >> allpodinfo_$CLUSTER.txt

    fi
    echo -e "\n" >> allpodinfo_$CLUSTER.txt
    unset POD_NAME CONFIG_MAP SECRET
done
