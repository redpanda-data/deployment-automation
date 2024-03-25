.PHONY: all keygen connect connect-simple build_aws build_gcp destroy_aws destroy_gcp ansible-prereqs collection role basic create-tls-cluster create-basic-cluster create-tiered-storage-cluster create-proxy-cluster install-rpk test-basic-cluster test-tls-cluster test-tiered-storage-cluster test-proxy-cluster

ARTIFACT_DIR := $(PWD)/artifacts
DEPLOYMENT_ID ?= devex-cicd
NUM_NODES ?= 3
ENABLE_MONITORING ?= true
TIERED_STORAGE_ENABLED ?= false
ALLOW_FORCE_DESTROY ?= true
VPC_ID ?=
BUCKET_NAME := $(subst _,-,$(DEPLOYMENT_ID))-bucket
DISTRO ?= ubuntu-focal
IS_USING_UNSTABLE ?= false

# RPK
RPK_PATH ?= $(ARTIFACT_DIR)/bin/rpk

# Terraform environment values
TERRAFORM_VERSION := 1.7.4
TERRAFORM_INSTALL_DIR := $(ARTIFACT_DIR)/terraform/$(TERRAFORM_VERSION)
ENABLE_CONNECT ?= false

# Ansible environment values
export ANSIBLE_VERSION := 2.11.12
export ANSIBLE_INSTALL_DIR := $(ARTIFACT_DIR)/ansible/$(ANSIBLE_VERSION)
export ANSIBLE_LOG_PATH := $(ARTIFACT_DIR)/logs/$(DEPLOYMENT_ID).log
export ANSIBLE_INVENTORY := $(ARTIFACT_DIR)/hosts_$(DEPLOYMENT_ID).ini
export ANSIBLE_COLLECTIONS_PATH := $(ARTIFACT_DIR)/collections
export ANSIBLE_ROLES_PATH := $(ARTIFACT_DIR)/roles

# hosts and keys
HOSTS_FILE ?= $(ARTIFACT_DIR)/hosts_$(DEPLOYMENT_ID).ini
PUBLIC_KEY ?= $(ARTIFACT_DIR)/testkey.pub
PRIVATE_KEY ?= $(ARTIFACT_DIR)/testkey

# copy_file environment values
RPM_VERSION ?= v1.0.0-7ae9d19
SERVER_DIR ?= /tmp
LOCAL_FILE := $(ARTIFACT_DIR)/redpanda-connect.x86_64.rpm
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
	@echo "Copying $(LOCAL_FILE).tar.gz to $(SERVER_DIR)"
	$(eval IPS_USERS=$(shell awk '/^\[connect\]/{f=1; next} /^\[/{f=0} f && /^[0-9]/{split($$2,a,"="); print a[2] "@" $$1}' $(HOSTS_FILE)))
	@echo $(IPS_USERS)
	@for IP_USER in $(IPS_USERS); do \
		scp -o StrictHostKeyChecking=no -i "$(PRIVATE_KEY)" "$(LOCAL_FILE)" "$$IP_USER:$(SERVER_DIR)"; \
	done


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
		-var='enable_connect=$(ENABLE_CONNECT)' \
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
		-var='enable_connect=$(ENABLE_CONNECT)' \
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
	@mkdir -p $(ANSIBLE_COLLECTIONS_PATH)
	@ansible-galaxy collection install -r $(PWD)/requirements.yml --force -p $(ANSIBLE_COLLECTIONS_PATH)

role:
	@mkdir -p $(ANSIBLE_ROLES_PATH)
	@ansible-galaxy role install -r $(PWD)/requirements.yml --force -p $(ANSIBLE_ROLES_PATH)

basic: ansible-prereqs
	@mkdir -p $(ARTIFACT_DIR)/logs
	@ansible-playbook ansible/provision-basic-cluster.yml --private-key $(PRIVATE_KEY) --inventory $(ANSIBLE_INVENTORY) --extra-vars is_using_unstable=$(IS_USING_UNSTABLE)

connect: ENABLE_CONNECT := true
connect: build_aws basic ansible-prereqs get_rpm copy_rpm
	@mkdir -p $(ARTIFACT_DIR)/logs
	@ansible-playbook ansible/deploy-connect.yml --private-key $(PRIVATE_KEY) --inventory $(ANSIBLE_INVENTORY) --extra-vars is_using_unstable=$(IS_USING_UNSTABLE)

connect-simple:
	@mkdir -p $(ARTIFACT_DIR)/logs
	@ansible-playbook ansible/deploy-connect.yml --private-key $(PRIVATE_KEY) --inventory $(ANSIBLE_INVENTORY) --extra-vars is_using_unstable=$(IS_USING_UNSTABLE)

create-tls-cluster: ansible-prereqs
	@mkdir -p $(ARTIFACT_DIR)/logs
	@ansible-playbook ansible/provision-tls-cluster.yml --private-key $(PRIVATE_KEY) --inventory $(ANSIBLE_INVENTORY) --extra-vars is_using_unstable=$(IS_USING_UNSTABLE) $(SKIP_TAGS) $(CLI_ARGS)

create-basic-cluster: ansible-prereqs
	@mkdir -p $(ARTIFACT_DIR)/logs
	@ansible-playbook ansible/provision-basic-cluster.yml --private-key $(PRIVATE_KEY) --inventory $(ANSIBLE_INVENTORY) --extra-vars is_using_unstable=$(IS_USING_UNSTABLE) $(SKIP_TAGS) $(CLI_ARGS)

monitor: ansible-prereqs
	@mkdir -p $(ARTIFACT_DIR)/logs
	@ansible-playbook ansible/deploy-prometheus-grafana.yml --private-key $(PRIVATE_KEY) --inventory $(ANSIBLE_INVENTORY) --extra-vars is_using_unstable=$(IS_USING_UNSTABLE) $(SKIP_TAGS) $(CLI_ARGS)

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
	@chmod 755

test-basic-cluster:
	@# Assemble the redpanda brokers by chopping up the hosts file
	$(eval REDPANDA_BROKERS := $(shell awk '/^\[redpanda\]/{f=1; next} /^$$/{f=0} f{print $$1}' "$(HOSTS_FILE)" | paste -sd ',' - | awk '{gsub(/,/,":9092,"); sub(/,$$/,":9092")}1'))

	$(eval REDPANDA_REGISTRY := $(shell awk '/^\[redpanda\]/{f=1; next} /^$$/{f=0} f{print $$1}' "$(HOSTS_FILE)" | paste -sd ',' - | awk '{gsub(/,/,":8081,"); sub(/,$$/,":8081")}1'))

	@echo $(REDPANDA_REGISTRY)
	@echo $(REDPANDA_BROKERS)
	@echo "checking cluster status"
	@$(RPK_PATH) cluster status --brokers $(REDPANDA_BROKERS) -v || exit 1

	@echo "creating topic"
	@$(RPK_PATH) topic create testtopic --brokers $(REDPANDA_BROKERS) -v || exit 1

	@echo "producing to topic"
	@echo squirrel | $(RPK_PATH) topic produce testtopic --brokers $(REDPANDA_BROKERS) -v || exit 1

	@echo "consuming from topic"
	@$(RPK_PATH) topic consume testtopic --brokers $(REDPANDA_BROKERS) -v -o :end | grep squirrel || exit 1

	@echo "testing schema registry"
	@for ip_port in $$(echo $(REDPANDA_REGISTRY) | tr ',' ' '); do curl $$ip_port/subjects ; done

test-tls-cluster: install-rpk
	@$(PWD)/.buildkite/scripts/test-tls-cluster.sh --hosts=$(ANSIBLE_INVENTORY) --cert=$(CA_CRT) --rpk=$(ARTIFACT_DIR)/bin/rpk

test-tiered-storage-cluster: install-rpk
	@$(PWD)/.buildkite/scripts/test-tiered-storage-cluster.sh --hosts=$(ANSIBLE_INVENTORY) --cert=$(CA_CRT) --rpk=$(ARTIFACT_DIR)/bin/rpk --bucket=$(BUCKET_NAME)

test-proxy-cluster:
	@$(PWD)/.buildkite/scripts/test-proxy-cluster.sh --hosts=$(ANSIBLE_INVENTORY) --cert=$(CA_CRT) --bucket=$(BUCKET_NAME) --sshkey=artifacts/testkey
