#!/bin/bash

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --tf_dir) TF_DIR="$2"; shift ;;
        --prefix) PREFIX="$2"; shift ;;
        --gcp_creds) GCP_CREDS="$2"; shift ;;
        --cluster_type) TASK_NAME="$2"; shift ;;
        --image) IMAGE="$2"; shift ;;
        --tiered) TIERED_STORAGE="$2"; shift ;;
        --destroy) DESTROY_TF_ENV="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# Check if TF_DIR and PREFIX are set
if [ -z "$TF_DIR" ] || [ -z "$PREFIX" ] || [ -z "$GCP_CREDS" ] || [ -z "$TASK_NAME" ]; then
    echo "TF_DIR : $TF_DIR"
    echo "TASK_NAME : $TASK_NAME"
    echo "TF_DIR, PREFIX, CLUSTER_TYPE and GCP_CREDS must be set. Exiting."
    exit 1
fi

cd "$TF_DIR" || exit 1
export HOSTS_FILE_DIR="$(pwd)/../../artifacts/hosts_gcp_${PREFIX}.ini"
export KEY_FILE="$(pwd)/../../artifacts/testkey"
if [ "$TF_DIR" == "gcp" ]; then
  export HOSTS_FILE_DIR="$(pwd)/../artifacts/hosts_gcp_${PREFIX}.ini"
  export KEY_FILE="$(pwd)/../artifacts/testkey"
fi

ssh-keygen -t rsa -b 4096 -C "test@redpanda.com" -N "" -f "$KEY_FILE" <<< y && chmod 0700 "$KEY_FILE"

# Trap to handle terraform destroy on exit
if [ ! "$DESTROY_TF_ENV" == "false" ]; then
  trap cleanup EXIT INT TERM
fi

cleanup() {
    error_code=$?
    terraform destroy --auto-approve --var="gcp_creds=$GCP_CREDS" --var="deployment_prefix=$PREFIX" --var="public_key_path=$KEY_FILE" --var="project_name=t" --var="hosts_file=$HOSTS_FILE_DIR"
    rm -rf /app/ansible/tls
    rm -f "$KEY_FILE"
    rm -f "${KEY_FILE}.pub"
    exit $error_code
}

terraform init
terraform apply --auto-approve  --var="image=$IMAGE" --var="deployment_prefix=$PREFIX" --var="gcp_creds=$GCP_CREDS" --var="tiered_storage_enabled=$TIERED_STORAGE" --var="public_key_path=$KEY_FILE.pub" --var="project_name=hallowed-ray-376320" --var="hosts_file=$HOSTS_FILE_DIR"
error_code=$?
if [ $error_code -ne 0 ]; then
  echo "error in terraform apply $TASK_NAME"
  exit 1
fi

echo "building cluster"
if [ "$TIERED_STORAGE" == "true" ]; then
  DEPLOYMENT_ID=$PREFIX DISTRO=$DISTRO IS_USING_UNSTABLE=$UNSTABLE SQUID_ACL_LOCALNET="10.0.0.0/24" CLOUD_PROVIDER="gcp" CLOUD_STORAGE_CREDENTIALS_SOURCE="gcp_instance_metadata" task "create-$TASK_NAME"
else
  DEPLOYMENT_ID=$PREFIX DISTRO=$DISTRO IS_USING_UNSTABLE=$UNSTABLE SQUID_ACL_LOCALNET="10.0.0.0/24" CLOUD_PROVIDER="gcp" task "create-$TASK_NAME"
fi

error_code=$?
if [ $error_code -ne 0 ]; then
  echo "error in ansible standup $TASK_NAME"
  exit 1
fi

echo "testing cluster"
DEPLOYMENT_ID=$PREFIX DISTRO=$DISTRO CLOUD_PROVIDER="gcp" task "test-$TASK_NAME"
error_code=$?
if [ $error_code -ne 0 ]; then
  echo "error in test $TASK_NAME"
  exit 1
fi

# Trap will handle destroy so just exit
exit $?
