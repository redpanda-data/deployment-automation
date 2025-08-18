# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This repository contains Terraform and Ansible configuration for automating the deployment of Redpanda clusters across multiple cloud providers (AWS, GCP, Azure, IBM). It provides infrastructure provisioning via Terraform and service deployment/configuration via Ansible playbooks.

## Common Development Commands

### Prerequisites Setup
```bash
# Install Ansible collections and roles
make ansible-prereqs
# OR manually:
export ANSIBLE_COLLECTIONS_PATH=${PWD}/artifacts/collections
export ANSIBLE_ROLES_PATH=${PWD}/artifacts/roles
ansible-galaxy collection install -r requirements.yml --force -p $ANSIBLE_COLLECTIONS_PATH
ansible-galaxy role install -r requirements.yml --force -p $ANSIBLE_ROLES_PATH
```

### Key Generation
```bash
make keygen  # Creates artifacts/testkey and artifacts/testkey.pub
```

### Infrastructure Deployment

#### AWS
```bash
# Build AWS infrastructure
make build-aws
# Full deployment with monitoring and console
make aws-rp

# With TLS
make ci-aws-rp-tls

# With tiered storage
make ci-aws-rp-tiered

# Clean up
make destroy-aws
```

#### GCP
```bash
# Build GCP infrastructure  
make build-gcp
# Full deployment
make ci-gcp-rp

# Clean up
make destroy-gcp
```

### Service Deployment
```bash
# Deploy Redpanda cluster
make cluster

# Deploy with TLS
make cluster-tls

# Deploy monitoring stack (Prometheus/Grafana)
make monitor

# Deploy Redpanda Console
make console

# Deploy Redpanda Connect
make deploy-connect
```

### Testing
```bash
# Test cluster connectivity and basic operations
make test-cluster

# Test TLS-enabled cluster
make test-cluster-tls

# Test schema registry
make test-schema
```

### Linting
```bash
make lint  # Runs ansible-lint
```

## Repository Architecture

### Directory Structure
- `ansible/` - Ansible playbooks for service deployment and configuration
  - `provision-cluster*.yml` - Main cluster deployment playbooks  
  - `deploy-monitor*.yml` - Monitoring stack deployment
  - `deploy-console*.yml` - Console deployment
  - `deploy-connect*.yml` - Connect deployment
  - `operation-*.yml` - Operational tasks (logging, restart, license)
  - `airgap/` - Air-gapped deployment configurations
  - `proxy/` - Proxy-based deployment configurations
  - `tls/` - TLS certificates and configurations

- `aws/`, `gcp/`, `azure/`, `ibm/` - Cloud-specific Terraform configurations
- `artifacts/` - Generated artifacts, logs, keys, and downloaded dependencies
  - `collections/` - Ansible collections
  - `roles/` - Ansible roles
  - `logs/` - Deployment logs

### Key Configuration Files
- `Makefile` - Primary build and deployment automation
- `requirements.yml` - Ansible collections and roles dependencies
- `ansible.cfg` - Ansible configuration with SSH optimizations
- `.ansible-lint` - Linting configuration with skip rules for production use

### Cloud Provider Support
Each cloud provider directory (`aws/`, `gcp/`, `azure/`, `ibm/`) contains:
- `main.tf` - Primary Terraform configuration
- `README.md` - Provider-specific documentation
- `private-test/` - Alternative configurations for private/proxy deployments

### Environment Variables
Key environment variables used by Make targets:
- `DEPLOYMENT_ID` - Unique identifier for the deployment
- `NUM_NODES` - Number of Redpanda broker nodes (default: 3)
- `ENABLE_MONITORING` - Enable Prometheus/Grafana stack
- `TIERED_STORAGE_ENABLED` - Enable tiered storage features
- `CLOUD_PROVIDER` - Target cloud provider (aws, gcp, azure, ibm)
- `ANSIBLE_INVENTORY` - Path to generated inventory file
- `REDPANDA_LICENSE` - License for Redpanda Enterprise features

### Ansible Integration
The repository uses a custom Redpanda Ansible collection (`redpanda.cluster`) along with community collections for monitoring (Grafana, Prometheus) and system setup. The collection is currently sourced from a development branch for testing new features.

### Development Workflow
1. Set environment variables for your target deployment
2. Generate SSH keys with `make keygen`
3. Deploy infrastructure with cloud-specific make targets
4. Deploy services with Ansible playbooks
5. Test deployment with provided test targets
6. Clean up with destroy targets

### TLS and Security
The repository supports both plaintext and TLS-encrypted deployments. TLS configurations use self-signed certificates generated in the `ansible/tls/` directory. All sensitive operations use proper SSH key management and secure defaults.