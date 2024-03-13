.PHONY: all keygen build_aws build_gcp destroy_aws destroy_gcp ansible-prereqs collection role basic create-tls-cluster create-basic-cluster create-tiered-storage-cluster create-proxy-cluster install-rpk test-basic-cluster test-tls-cluster test-tiered-storage-cluster test-proxy-cluster

ARTIFACT_DIR := $(PWD)/artifacts

PUBLIC_KEY_DEFAULT := $(ARTIFACT_DIR)/testkey.pub
PRIVATE_KEY_DEFAULT := $(ARTIFACT_DIR)/testkey
PUBLIC_KEY ?= $(PUBLIC_KEY_DEFAULT)
PRIVATE_KEY ?= $(PRIVATE_KEY_DEFAULT)
DEPLOYMENT_ID ?= devex-cicd
NUM_NODES ?= 3
ENABLE_MONITORING ?= true
TIERED_STORAGE_ENABLED ?= false
ALLOW_FORCE_DESTROY ?= true
VPC_ID ?=
BUCKET_NAME := $(subst _,-,$(DEPLOYMENT_ID))-bucket
DISTRO ?= ubuntu-focal
IS_USING_UNSTABLE ?= false

# Terraform environment values
TERRAFORM_VERSION := 1.7.4
TERRAFORM_INSTALL_DIR := $(ARTIFACT_DIR)/terraform/$(TERRAFORM_VERSION)

# Ansible environment values
export ANSIBLE_VERSION := 2.11.12
export ANSIBLE_INSTALL_DIR := $(ARTIFACT_DIR)/ansible/$(ANSIBLE_VERSION)
export ANSIBLE_LOG_PATH := $(ARTIFACT_DIR)/logs/$(DEPLOYMENT_ID).log
export ANSIBLE_INVENTORY := $(ARTIFACT_DIR)/hosts_$(DEPLOYMENT_ID).ini
export ANSIBLE_COLLECTIONS_PATHS := $(ARTIFACT_DIR)/collections
export ANSIBLE_ROLES_PATH := $(ARTIFACT_DIR)/roles

# copy_file environment values
RPM_VERSION := v1.0.0-7ae9d19
SSH_USER := ${SSH_USER}
TARGET_SERVER := example.com
SERVER_DIR := /tmp
LOCAL_FILE := $(ARTIFACT_DIR)/redpanda-connect.rpm
TOKEN := ${TOKEN}
DL_LINK :=  https://dl.redpanda.com/$(TOKEN)/connectors-artifacts/raw/names/redpanda-connectors/versions/$(RPM_VERSION)/redpanda-connectors-$(RPM_VERSION).x86_64.rpm

INSTANCE_TYPE_AWS ?= i3.2xlarge
MACHINE_ARCH ?= x86_64

export TF_IN_AUTOMATION := $(CI)
export AWS_ACCESS_KEY_ID := $(if $(AWS_ACCESS_KEY_ID),$(AWS_ACCESS_KEY_ID),$(DA_AWS_ACCESS_KEY_ID))
export AWS_SECRET_ACCESS_KEY := $(if $(AWS_SECRET_ACCESS_KEY),$(AWS_SECRET_ACCESS_KEY),$(DA_AWS_SECRET_ACCESS_KEY))
export AWS_DEFAULT_REGION ?= us-west-2

all: keygen build_aws ansible-prereqs

ansible-prereqs: collection role
	@echo "Ansible prereqs installed"

basic_aws: build_aws create-basic-cluster

teardown: destroy_aws destroy_gcp

get_rpm:
	curl -o $(LOCAL_FILE) $(DL_LINK)

copy_rpm:

	@scp -i $(PRIVATE_KEY) $(LOCAL_FILE) $(SSH_USER)@$(TARGET_SERVER):$(SERVER_DIR)

keygen:
	@ssh-keygen -t rsa -b 4096 -C "$(SSH_EMAIL)" -N "" -f artifacts/testkey <<< y && chmod 0700 artifacts/testkey

build_aws:
	@cd aws/$(TF_DIR) && \
	terraform init && \
	terraform apply -auto-approve \
		-var='deployment_prefix=$(DEPLOYMENT_ID)' \
		-var='public_key_path=$(PUBLIC_KEY)' \
		-var='broker_count=$(NUM_NODES)' \
		-var='enable_monitoring=$(ENABLE_MONITORING)' \
		-var='tiered_storage_enabled=$(TIERED_STORAGE_ENABLED)' \
		-var='allow_force_destroy=$(ALLOW_FORCE_DESTROY)' \
		-var='vpc_id=$(VPC_ID)' \
		-var='distro=$(DISTRO)' \
		-var='hosts_file=$(ANSIBLE_INVENTORY)' \
		-var='machine_architecture=$(MACHINE_ARCH)' \
		-var='instance_type=$(INSTANCE_TYPE_AWS)'

build_gcp:
	@cd gcp/$(TF_DIR) && \
	terraform init && \
	terraform apply -auto-approve \
		-var='deployment_prefix=$(DEPLOYMENT_ID)' \
		-var='public_key_path=$(PUBLIC_KEY)' \
		-var='broker_count=$(NUM_NODES)' \
		-var='enable_monitoring=$(ENABLE_MONITORING)' \
		-var='tiered_storage_enabled=$(TIERED_STORAGE_ENABLED)' \
		-var='allow_force_destroy=$(ALLOW_FORCE_DESTROY)' \
		-var='vpc_id=$(VPC_ID)' \
		-var='distro=$(DISTRO)' \
		-var='hosts_file=$(ANSIBLE_INVENTORY)' \
		-var='machine_architecture=$(MACHINE_ARCH)' \
		-var='instance_type=$(INSTANCE_TYPE)'

destroy_aws:
	@cd aws/$(TF_DIR) && \
	terraform init && \
	terraform destroy -auto-approve \
		-var='deployment_prefix=$(DEPLOYMENT_ID)' \
		-var='public_key_path=$(PUBLIC_KEY)' \
		-var='broker_count=$(NUM_NODES)' \
		-var='enable_monitoring=$(ENABLE_MONITORING)' \
		-var='tiered_storage_enabled=$(TIERED_STORAGE_ENABLED)' \
		-var='allow_force_destroy=$(ALLOW_FORCE_DESTROY)' \
		-var='vpc_id=$(VPC_ID)' \
		-var='distro=$(DISTRO)' \
		-var='hosts_file=$(ANSIBLE_INVENTORY)' \
		-var='machine_architecture=$(MACHINE_ARCH)' \
		-var='instance_type=$(INSTANCE_TYPE)'

destroy_gcp:
	@cd gcp/$(TF_DIR) && \
	terraform init && \
	terraform destroy -auto-approve \
		-var='deployment_prefix=$(DEPLOYMENT_ID)' \
		-var='public_key_path=$(PUBLIC_KEY)' \
		-var='broker_count=$(NUM_NODES)' \
		-var='enable_monitoring=$(ENABLE_MONITORING)' \
		-var='tiered_storage_enabled=$(TIERED_STORAGE_ENABLED)' \
		-var='allow_force_destroy=$(ALLOW_FORCE_DESTROY)' \
		-var='vpc_id=$(VPC_ID)' \
		-var='distro=$(DISTRO)' \
		-var='hosts_file=$(ANSIBLE_INVENTORY)' \
		-var='machine_architecture=$(MACHINE_ARCH)' \
		-var='instance_type=$(INSTANCE_TYPE)'

collection:
	@mkdir -p $(ANSIBLE_COLLECTIONS_PATHS)
	@ansible-galaxy collection install -r $(PWD)/requirements.yml --force -p $(ANSIBLE_COLLECTIONS_PATHS)

role:
	@mkdir -p $(ANSIBLE_ROLES_PATH)
	@ansible-galaxy role install -r $(PWD)/requirements.yml --force -p $(ANSIBLE_ROLES_PATH)

basic: ansible-prereqs
	@mkdir -p $(ARTIFACT_DIR)/logs
	@ansible-playbook ansible/provision-basic-cluster.yml --private-key $(PRIVATE_KEY) --inventory $(ANSIBLE_INVENTORY) --extra-vars is_using_unstable=$(IS_USING_UNSTABLE)

create-tls-cluster: ansible-prereqs
	@mkdir -p $(ARTIFACT_DIR)/logs
	@ansible-playbook ansible/provision-tls-cluster.yml --private-key $(PRIVATE_KEY) --inventory $(ANSIBLE_INVENTORY) --extra-vars is_using_unstable=$(IS_USING_UNSTABLE) $(SKIP_TAGS) $(CLI_ARGS)

create-basic-cluster: ansible-prereqs
	@mkdir -p $(ARTIFACT_DIR)/logs
	@ansible-playbook ansible/provision-basic-cluster.yml --private-key $(PRIVATE_KEY) --inventory $(ANSIBLE_INVENTORY) --extra-vars is_using_unstable=$(IS_USING_UNSTABLE) $(SKIP_TAGS) $(CLI_ARGS)

create-tiered-storage-cluster: ansible-prereqs
	@mkdir -p $(ARTIFACT_DIR)/logs
	@ansible-playbook ansible/provision-tiered-storage-cluster.yml --private-key $(PRIVATE_KEY) --inventory $(ANSIBLE_INVENTORY) --extra-vars is_using_unstable=$(IS_USING_UNSTABLE) $(SKIP_TAGS) --extra-vars cloud_storage_credentials_source='$(CLOUD_STORAGE_CREDENTIALS_SOURCE)' --extra-vars redpanda='{\"cluster\":{\"cloud_storage_segment_max_upload_interval_sec\":\"$(SEGMENT_UPLOAD_INTERVAL)\"}}' $(CLI_ARGS)

create-proxy-cluster: ansible-prereqs
	@mkdir -p $(ARTIFACT_DIR)/logs
	@ansible-playbook ansible/proxy/provision-private-proxied-cluster.yml --private-key $(PRIVATE_KEY) --inventory $(ANSIBLE_INVENTORY) --extra-vars is_using_unstable=$(IS_USING_UNSTABLE) --extra-vars '{\"squid_acl_localnet\": [\"$(SQUID_ACL_LOCALNET)\"]}' --extra-vars redpanda='{\"cluster\":{\"cloud_storage_segment_max_upload_interval_sec\":\"$(SEGMENT_UPLOAD_INTERVAL)\"}}' $(SKIP_TAGS) $(CLI_ARGS)

install-rpk:
	@mkdir -p $(ARTIFACT_DIR)/tmp
	@curl -L https://github.com/redpanda-data/redpanda/releases/latest/download/rpk-linux-amd64.zip -o $(ARTIFACT_DIR)/tmp/rpk-linux-amd64.zip
	@mkdir -p $(ARTIFACT_DIR)/bin
	@unzip -o $(ARTIFACT_DIR)/tmp/rpk-linux-amd64.zip -d $(ARTIFACT_DIR)/bin/
	@chmod 755 $(ARTIFACT_DIR)/bin/rpk

test-basic-cluster: install-rpk
	@$(PWD)/.buildkite/scripts/test-basic-cluster.sh --hosts=$(ANSIBLE_INVENTORY) --rpk=$(ARTIFACT_DIR)/bin/rpk

test-tls-cluster: install-rpk
	@$(PWD)/.buildkite/scripts/test-tls-cluster.sh --hosts=$(ANSIBLE_INVENTORY) --cert=$(CA_CRT) --rpk=$(ARTIFACT_DIR)/bin/rpk

test-tiered-storage-cluster: install-rpk
	@$(PWD)/.buildkite/scripts/test-tiered-storage-cluster.sh --hosts=$(ANSIBLE_INVENTORY) --cert=$(CA_CRT) --rpk=$(ARTIFACT_DIR)/bin/rpk --bucket=$(BUCKET_NAME)

test-proxy-cluster:
	@$(PWD)/.buildkite/scripts/test-proxy-cluster.sh --hosts=$(ANSIBLE_INVENTORY) --cert=$(CA_CRT) --bucket=$(BUCKET_NAME) --sshkey=artifacts/testkey
