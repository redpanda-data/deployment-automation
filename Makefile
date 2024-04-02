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
CA_CRT ?= ansible/tls/ca/ca.crt

# RPK
RPK_PATH ?= $(ARTIFACT_DIR)/bin/rpk

# Terraform environment values
TERRAFORM_VERSION := 1.7.4
TERRAFORM_INSTALL_DIR := $(ARTIFACT_DIR)/terraform/$(TERRAFORM_VERSION)
ENABLE_CONNECT ?= false

# Ansible environment values
export ANSIBLE_VERSION := 2.16.4
export ANSIBLE_INSTALL_DIR := $(ARTIFACT_DIR)/ansible/$(ANSIBLE_VERSION)
export ANSIBLE_LOG_PATH := $(ARTIFACT_DIR)/logs/$(DEPLOYMENT_ID).log
export ANSIBLE_INVENTORY := $(ARTIFACT_DIR)/hosts_$(DEPLOYMENT_ID).ini
export ANSIBLE_COLLECTIONS_PATH := $(ARTIFACT_DIR)/collections
export ANSIBLE_ROLES_PATH := $(ARTIFACT_DIR)/roles

# hosts and keys
HOSTS_FILE ?= $(ARTIFACT_DIR)/hosts_$(DEPLOYMENT_ID).ini
PUBLIC_KEY ?= $(ARTIFACT_DIR)/testkey.pub
PRIVATE_KEY ?= $(ARTIFACT_DIR)/testkey

# gcp env
GOOGLE_PROJECT_ID ?= "hallowed-ray-376320"

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
test-cluster-tiered-storage-aws: test-cluster-tls test-storage-aws
test-cluster-tiered-storage-gcp: test-cluster-tls test-storage-gcp

.PHONY: ansible-prereqs
ansible-prereqs: collection role
	@echo "Ansible prereqs installed"

.PHONY: teardown
teardown: destroy_aws destroy_gcp

.PHONY: get_rpm
get_rpm:
	curl -o $(LOCAL_FILE) $(DL_LINK)

.PHONY: copy_rpm
copy_rpm:
	@echo "Copying $(LOCAL_FILE).tar.gz to $(SERVER_DIR)"
	$(eval IPS_USERS=$(shell awk '/^\[connect\]/{f=1; next} /^\[/{f=0} f && /^[0-9]/{split($$2,a,"="); print a[2] "@" $$1}' $(HOSTS_FILE)))
	@echo $(IPS_USERS)
	@for IP_USER in $(IPS_USERS); do \
		scp -o StrictHostKeyChecking=no -i "$(PRIVATE_KEY)" "$(LOCAL_FILE)" "$$IP_USER:$(SERVER_DIR)"; \
	done

.PHONY: keygen
keygen:
	@ssh-keygen -t rsa -b 4096 -C "$(SSH_EMAIL)" -N "" -f artifacts/testkey <<< y && chmod 0700 artifacts/testkey

.PHONY: build_aws
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

GCP_IMAGE ?= ubuntu-os-cloud/ubuntu-2204-lts
GCP_INSTANCE_TYPE ?= n2-standard-2
GCP_CREDS ?= $(shell echo $$GCP_CREDS)
.PHONY: build_gcp
build_gcp:
	@cd gcp/$(TF_DIR) && \
	terraform init && \
	terraform apply -auto-approve \
		-var='deployment_prefix=$(DEPLOYMENT_ID)' \
		-var='public_key_path=$(PUBLIC_KEY)' \
		-var='broker_count=$(NUM_NODES)' \
		-var='enable_monitoring=$(ENABLE_MONITORING)' \
		-var='tiered_storage_enabled=$(TIERED_STORAGE_ENABLED)' \
		-var='image=$(GCP_IMAGE)' \
		-var='hosts_file=$(ANSIBLE_INVENTORY)' \
		-var='machine_type=$(GCP_INSTANCE_TYPE)' \
		-var='gcp_creds=$(GCP_CREDS)'

.PHONY: destroy_aws
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

.PHONY: destroy_gcp
destroy_gcp:
	@cd gcp/$(TF_DIR) && \
	terraform init && \
	terraform destroy -auto-approve \
		-var='deployment_prefix=$(DEPLOYMENT_ID)' \
		-var='public_key_path=$(PUBLIC_KEY)' \
		-var='broker_count=$(NUM_NODES)' \
		-var='enable_monitoring=$(ENABLE_MONITORING)' \
		-var='tiered_storage_enabled=$(TIERED_STORAGE_ENABLED)' \
		-var='image=$(GCP_IMAGE)' \
		-var='hosts_file=$(ANSIBLE_INVENTORY)' \
		-var='machine_type=$(GCP_INSTANCE_TYPE)' \
		-var='gcp_creds=$(GCP_CREDS)'

.PHONY: collection
collection:
	@mkdir -p $(ANSIBLE_COLLECTIONS_PATH)
	@ansible-galaxy collection install -r $(PWD)/requirements.yml --force -p $(ANSIBLE_COLLECTIONS_PATH)

.PHONY: role
role:
	@mkdir -p $(ANSIBLE_ROLES_PATH)
	@ansible-galaxy role install -r $(PWD)/requirements.yml --force -p $(ANSIBLE_ROLES_PATH)

.PHONY: monitor
monitor: ansible-prereqs
	@mkdir -p $(ARTIFACT_DIR)/logs
	@ansible-playbook ansible/deploy-monitor.yml --private-key $(PRIVATE_KEY) --inventory $(ANSIBLE_INVENTORY) --extra-vars is_using_unstable=$(IS_USING_UNSTABLE)

.PHONY: monitor-tls
monitor-tls: ansible-prereqs
	@mkdir -p $(ARTIFACT_DIR)/logs
	@ansible-playbook ansible/deploy-monitor-tls.yml --private-key $(PRIVATE_KEY) --inventory $(ANSIBLE_INVENTORY) --extra-vars is_using_unstable=$(IS_USING_UNSTABLE)

.PHONY: connect
connect: ENABLE_CONNECT := true
connect: build_aws cluster monitor get_rpm copy_rpm
	@mkdir -p $(ARTIFACT_DIR)/logs
	@ansible-playbook ansible/deploy-connect.yml --private-key $(PRIVATE_KEY) --inventory $(ANSIBLE_INVENTORY) --extra-vars is_using_unstable=$(IS_USING_UNSTABLE)

.PHONY: connect-simple
connect-simple: ENABLE_CONNECT := true
connect-simple: ansible-prereqs
	@mkdir -p $(ARTIFACT_DIR)/logs
	@ansible-playbook ansible/deploy-connect.yml --private-key $(PRIVATE_KEY) --inventory $(ANSIBLE_INVENTORY) --extra-vars is_using_unstable=$(IS_USING_UNSTABLE)

.PHONY: connect-simple-tls
connect-simple-tls: ENABLE_CONNECT := true
connect-simple-tls: ansible-prereqs
	@mkdir -p $(ARTIFACT_DIR)/logs
	@ansible-playbook ansible/deploy-connect-tls.yml --private-key $(PRIVATE_KEY) --inventory $(ANSIBLE_INVENTORY) --extra-vars is_using_unstable=$(IS_USING_UNSTABLE)


.PHONY: connect-tls
connect-tls: ENABLE_CONNECT := true
connect-tls: build_aws cluster-tls monitor-tls get_rpm copy_rpm
	@mkdir -p $(ARTIFACT_DIR)/logs
	@ansible-playbook ansible/deploy-connect-tls.yml --private-key $(PRIVATE_KEY) --inventory $(ANSIBLE_INVENTORY) --extra-vars is_using_unstable=$(IS_USING_UNSTABLE)


MAC_RPK := "https://github.com/redpanda-data/redpanda/releases/latest/download/rpk-darwin-amd64.zip"
LINUX_RPK := "https://github.com/redpanda-data/redpanda/releases/latest/download/rpk-linux-amd64.zip"

.PHONY: install-rpk
install-rpk:
	@mkdir -p $(ARTIFACT_DIR)/tmp
	@mkdir -p $(ARTIFACT_DIR)/bin
ifeq ($(shell uname),Darwin)
	@curl -L $(MAC_RPK) -o $(ARTIFACT_DIR)/tmp/rpk.zip
else
	@curl -L $(LINUX_RPK) -o $(ARTIFACT_DIR)/tmp/rpk.zip
endif
	@unzip -o $(ARTIFACT_DIR)/tmp/rpk.zip -d $(ARTIFACT_DIR)/bin/
	@chmod 755 $(ARTIFACT_DIR)/bin/rpk
	@rm $(ARTIFACT_DIR)/tmp/rpk.zip

.PHONY: cluster
cluster: ansible-prereqs
	@mkdir -p $(ARTIFACT_DIR)/logs
	@ansible-playbook ansible/provision-cluster.yml --private-key $(PRIVATE_KEY) --inventory $(ANSIBLE_INVENTORY) --extra-vars is_using_unstable=$(IS_USING_UNSTABLE)

.PHONY: test-cluster
test-cluster:
	@# Assemble the redpanda brokers by chopping up the hosts file
	chmod 775 $(RPK_PATH)
	echo $(RPK_PATH)
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

.PHONY: cluster-tls
cluster-tls: ansible-prereqs
	@mkdir -p $(ARTIFACT_DIR)/logs
	 ansible-playbook ansible/provision-cluster-tls.yml --private-key $(PRIVATE_KEY) --extra-vars is_using_unstable=$(IS_USING_UNSTABLE)

.PHONY: test-cluster-tls
test-cluster-tls:
	$(eval REDPANDA_BROKERS := $(shell sed -n '/^\[redpanda\]/,/^$$/p' "$(ANSIBLE_INVENTORY)" | \
		grep 'private_ip=' | \
		cut -d' ' -f1 | \
		sed 's/$$/:9092/' | \
		tr '\n' ',' | \
		sed 's/,$$/\n/'))

	$(eval REDPANDA_REGISTRY := $(shell sed -n '/^\[redpanda\]/,/^$$/p' "$(ANSIBLE_INVENTORY)" | \
		grep 'private_ip=' | \
		cut -d' ' -f1 | \
		sed 's/$$/:8081/' | \
		tr '\n' ',' | \
		sed 's/,$$/\n/'))

	@echo "checking cluster status"
	@$(ARTIFACT_DIR)/bin/rpk cluster status --brokers "$(REDPANDA_BROKERS)" --tls-truststore "$(CA_CRT)" -v || exit 1

	@echo "creating topic"
	@$(ARTIFACT_DIR)/bin/rpk topic create testtopic --brokers "$(REDPANDA_BROKERS)" --tls-truststore "$(CA_CRT)" -v || exit 1

	@echo "producing to topic"
	@echo squirrels | $(ARTIFACT_DIR)/bin/rpk topic produce testtopic --brokers "$(REDPANDA_BROKERS)" --tls-truststore "$(CA_CRT)" -v || exit 1

	@echo "consuming from topic"
	@$(ARTIFACT_DIR)/bin/rpk topic consume testtopic --brokers "$(REDPANDA_BROKERS)" --tls-truststore "$(CA_CRT)" -v -o :end | grep squirrels || exit 1

	@echo "testing schema registry"
	@for ip_port in $$(echo $(REDPANDA_REGISTRY) | tr ',' ' '); do \
		curl $$ip_port/subjects -k --cacert "$(CA_CRT)"; \
	done

SEGMENT_UPLOAD_INTERVAL ?= "1"
CLOUD_STORAGE_CREDENTIALS_SOURCE ?= "aws_instance_metadata"

.PHONY: cluster-tiered-storage
cluster-tiered-storage: ansible-prereqs
	@mkdir -p $(ARTIFACT_DIR)/logs
	 ansible-playbook ansible/provision-cluster-tiered-storage.yml --private-key $(PRIVATE_KEY) --extra-vars is_using_unstable=$(IS_USING_UNSTABLE) --extra-vars segment_upload_interval=$(SEGMENT_UPLOAD_INTERVAL) --extra-vars cloud_storage_credentials_source=$(CLOUD_STORAGE_CREDENTIALS_SOURCE)

.PHONY: test-cluster-tiered-storage
test-storage-gcp:
	@echo "$DEVEX_GCP_CREDS_BASE64" | base64 -d > /tmp/gcp_creds.json
	export GOOGLE_APPLICATION_CREDENTIALS="/tmp/gcp_creds.json"
	export CLOUDSDK_CORE_PROJECT=$(GOOGLE_PROJECT_ID)
	@gcloud auth activate-service-account --key-file=$(GOOGLE_APPLICATION_CREDENTIALS)
	@gcloud storage ls | grep ${BUCKET_NAME%-bucket}

.PHONY: test-storage-aws
test-storage-aws:
	@aws s3api list-objects-v2 --bucket "${BUCKET_NAME}" --region us-west-2 --max-items 1 --output text --query 'Contents[0].Key' | grep testtopic || exit 1

.PHONY: cluster-proxy
cluster-proxy: ansible-prereqs
	@mkdir -p $(ARTIFACT_DIR)/logs
	@ansible-playbook ansible/proxy/provision-private-proxied-cluster.yml --private-key $(PRIVATE_KEY) --inventory $(ANSIBLE_INVENTORY) --extra-vars is_using_unstable=$(IS_USING_UNSTABLE) --extra-vars '{\"squid_acl_localnet\": [\"$(SQUID_ACL_LOCALNET)\"]}' --extra-vars redpanda='{\"cluster\":{\"cloud_storage_segment_max_upload_interval_sec\":\"$(SEGMENT_UPLOAD_INTERVAL)\"}}' $(SKIP_TAGS) $(CLI_ARGS)

.PHONY: test-cluster-proxy
test-cluster-proxy:
	$(eval REDPANDA_BROKERS := $(shell sed -n '/^\[redpanda\]/,/^$$/p' "$(PATH_TO_HOSTS_FILE)" | \
		grep 'private_ip=' | \
		cut -d' ' -f1 | \
		sed 's/$$/:9092/' | \
		tr '\n' ',' | \
		sed 's/,$$/\n/'))

	$(eval CLIENT_SSH_USER := $(shell sed -n '/\[redpanda\]/,/\[/p' "$(PATH_TO_HOSTS_FILE)" | \
		grep ansible_user | \
		head -n1 | \
		tr ' ' '\n' | \
		grep ansible_user | \
		cut -d'=' -f2))

	$(eval CLIENT_PUBLIC_IP := $(shell sed -n '/^\[client\]/,/^$$/p' "$(PATH_TO_HOSTS_FILE)" | \
		grep 'private_ip=' | \
		cut -f1 -d' '))

	@echo "checking cluster status"
	@ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -i "$(SSHKEY)" "$(CLIENT_SSH_USER)@$(CLIENT_PUBLIC_IP)" 'rpk cluster status --brokers "$(REDPANDA_BROKERS)" --tls-truststore "$(PATH_TO_CA_CRT)" -v' || exit 1

	@echo "creating topic"
	@ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -i "$(SSHKEY)" "$(CLIENT_SSH_USER)@$(CLIENT_PUBLIC_IP)" 'rpk topic create testtopic --brokers "$(REDPANDA_BROKERS)" --tls-truststore "$(PATH_TO_CA_CRT)" -v' || exit 1

	@echo "producing to topic"
	@ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -i "$(SSHKEY)" "$(CLIENT_SSH_USER)@$(CLIENT_PUBLIC_IP)" 'echo squirrels | rpk topic produce testtopic --brokers "$(REDPANDA_BROKERS)" --tls-truststore "$(PATH_TO_CA_CRT)" -v' || exit 1

	@sleep 30

	@echo "consuming from topic"
	$(eval testoutput := $(shell ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -i "$(SSHKEY)" "$(CLIENT_SSH_USER)@$(CLIENT_PUBLIC_IP)" 'rpk topic consume testtopic --brokers "$(REDPANDA_BROKERS)" --tls-truststore "$(PATH_TO_CA_CRT)" -v -o :end'))
	@echo "$(testoutput)" | grep squirrels || exit 1
