#!/bin/bash

# Function to handle the SIGINT signal (Ctrl+C)
interrupt_handler() {
    echo "Script interrupted. Cleaning up..."
    exit 0
}

# Register the interrupt handler function for the SIGINT signal
trap interrupt_handler SIGINT


echo "This script will expose sensitive data, do not store the output file in shared environments or share with anyone. Only use for comparison purposes and destroy once you are done!"
read -p "Enter the cluster name: " cluster_name

# Switch context to the specified cluster
kubectl config use-context $cluster_name

# Get current date and time
current_datetime=$(date +%Y-%m-%d_%H-%M-%S)

# Create output file name
output_file="$cluster_name-_-$current_datetime.txt"

# Get all namespaces in the cluster
namespaces='cloud react-portal reports sso-web-app tortle-admin uploader'

# Loop through each namespace
for namespace in $namespaces; do
    echo "Namespace: $namespace" >> "$output_file"
    echo "_______________________" >> "$output_file"

    # Get deployments in the namespace
    deployments=$(kubectl get deployment -n $namespace -o jsonpath='{.items[*].metadata.name}')

    # Loop through each deployment
    for deployment in $deployments; do
        echo "Deployment: $deployment" >> "$output_file"

        # Get environment variables from configmap
        configmap_env=$(kubectl get deployment $deployment -n $namespace -o jsonpath='{.spec.template.spec.containers[*].envFrom[?(@.configMapRef)]}')

        # Check if there are configmaps in envFrom
        if [[ -n $configmap_env ]]; then
            # Check if there is only one configmap envFrom item
            if echo "$configmap_env" | jq -e 'type == "object"' > /dev/null; then
                configmap_name=$(echo "$configmap_env" | jq -r '.configMapRef.name')
                if [[ $configmap_name != "null" ]]; then
                    configmap_data=$(kubectl get configmap $configmap_name -n $namespace -o jsonpath='{.data}')
                    echo "ConfigMap: $configmap_name" >> "$output_file"
                    echo "$configmap_data" | jq -r 'to_entries[] | "\(.key)=\(.value)"' >> "$output_file"
                fi
            else
                # Loop through each configmap envFrom item
                while IFS= read -r item; do
                    configmap_name=$(echo "$item" | jq -r '.configMapRef.name')
                    if [[ $configmap_name != "null" ]]; then
                        configmap_data=$(kubectl get configmap $configmap_name -n $namespace -o jsonpath='{.data}')
                        echo "ConfigMap: $configmap_name" >> "$output_file"
                        echo "$configmap_data" | jq -r 'to_entries[] | "\(.key)=\(.value)"' >> "$output_file"
                    fi
                done <<< "$(echo "$configmap_env" | jq -r '.[] | @json')"
            fi
        fi

        # Get environment variables from secret
        secret_env=$(kubectl get deployment $deployment -n $namespace -o jsonpath='{.spec.template.spec.containers[*].envFrom[?(@.secretRef)]}')

        # Check if there are secrets in envFrom
        if [[ -n $secret_env ]]; then
            # Check if there is only one secret envFrom item
            if echo "$secret_env" | jq -e 'type == "object"' > /dev/null; then
                secret_name=$(echo "$secret_env" | jq -r '.secretRef.name')
                if [[ $secret_name != "null" ]]; then
                     secret_data=$(kubectl get secret $secret_name -o json -n $namespace -o json  | jq '.data | to_entries | map("\(.key)=\(.value|@base64d|tostring)") | .[]' -r)
                    echo "Secret: $secret_name" >> "$output_file"
                    echo "$secret_data"  >> "$output_file"
                fi
            else
                # Loop through each secret envFrom item
                while IFS= read -r item; do
                    secret_name=$(echo "$item" | jq -r '.secretRef.name')
                    if [[ $secret_name != "null" ]]; then
                         secret_data=$(kubectl get secret $secret_name -o json -n $namespace -o json  | jq '.data | to_entries | map("\(.key)=\(.value|@base64d|tostring)") | .[]' -r)
                        echo "Secret: $secret_name" >> "$output_file"
                        echo "$secret_data"  >> "$output_file"
                    fi
                done <<< "$(echo "$secret_env" | jq -r '.[] | @json')"
            fi
        fi

        # Get environment variables
        env=$(kubectl get deployment $deployment -n $namespace -o jsonpath='{.spec.template.spec.containers[*].env}')

        # Check if there are variables in env
        if [[ -n $env ]]; then
            # Loop through each env item
            while IFS= read -r item; do
                name=$(echo "$item" | jq -r '.name')
                value_from=$(echo "$item" | jq -r '.valueFrom')
                if echo "$value_from" | jq -e 'has("configMapKeyRef")' > /dev/null; then
                    configmap_key=$(echo "$value_from" | jq -r '.configMapKeyRef.key')
                    configmap_name=$(echo "$value_from" | jq -r '.configMapKeyRef.name')
                    if [[ $configmap_name != "null" ]]; then
                        value=$(kubectl get configmap $configmap_name -n $namespace -o jsonpath="{.data.$configmap_key}")
                        echo "$name=$value" >> "$output_file"
                    fi
                elif echo "$value_from" | jq -e 'has("secretKeyRef")' > /dev/null; then
                    secret_key=$(echo "$value_from" | jq -r '.secretKeyRef.key')
                    secret_name=$(echo "$value_from" | jq -r '.secretKeyRef.name')
                    if [[ $secret_name != "null" ]]; then
                        secret_data=$(kubectl get secret $secret_name -n $namespace -o jsonpath="{.data.$secret_key}")
                        echo "$name=$(echo "$secret_data" | awk '{printf "%s", $2}' | base64 --decode)" >> "$output_file"
                    fi
                else
                    value=$(echo "$item" | jq -r '.value')
                    echo "$name=$value" >> "$output_file"
                fi
            done <<< "$(echo "$env" | jq -r '.[] | @json')"
        fi

        echo >> "$output_file"
    done

    echo >> "$output_file"
done