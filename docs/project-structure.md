# HomeLab DevOps Platform Project Structure for Synology DS923+

This document provides an overview of the project structure, explaining the purpose and organization of various files and directories for the HomeLab DevOps Platform deployed on Synology DS923+.

## Directory Structure

```
homelab-devops/
├── config/                   # Configuration files
│   ├── default.conf          # Default configuration variables
│   ├── custom.conf           # Custom configuration overrides (optional)
│   ├── vault_credentials.conf # Generated Vault credentials
│   ├── certs/                # Self-signed certificates
│   │   ├── homelab.crt       # Certificate file
│   │   └── homelab.key       # Private key file
│   ├── oidc/                 # OIDC-specific configuration files
│   │   └── clients.json      # OIDC client configurations
│   └── volumes.hcl           # Nomad volume definitions
├── docs/                     # Documentation
│   ├── 00-prerequisites.md   # Stage 0 prerequisites and setup
│   ├── 01-setup-directories.md # Setup directories documentation
│   ├── 02-volume-configuration.md # Volume configuration documentation
│   ├── 03-consul-setup.md    # Consul documentation
│   ├── 04-traefik-setup.md   # Traefik documentation
│   ├── 05-vault-setup.md     # Vault documentation
│   ├── ...                   # Other component documentation
│   ├── architecture-diagram.md # System architecture diagram
│   ├── backup-recovery.md    # Backup and recovery procedures
│   ├── project-structure.md  # This file
│   ├── synology-considerations.md # Synology-specific considerations
│   ├── self-signed-certificates.md # Certificate management
│   ├── storage-configuration.md # Storage configuration
│   ├── troubleshooting.md    # Troubleshooting guide
│   └── extending-the-platform.md # Extension and customization guide
├── jobs/                     # Nomad job definitions
│   ├── consul.hcl            # Consul job
│   ├── traefik.hcl           # Traefik job
│   ├── vault.hcl             # Vault job
│   ├── registry.hcl          # Docker Registry job
│   ├── prometheus.hcl        # Prometheus job
│   ├── grafana.hcl           # Grafana job
│   ├── loki.hcl              # Loki job
│   ├── promtail.hcl          # Promtail job
│   ├── keycloak.hcl          # Keycloak job
│   ├── oidc-proxy.hcl        # OIDC Proxy job
│   └── homepage.hcl          # Homepage dashboard job
├── logs/                     # Log files
│   ├── install.log           # Installation log
│   └── platform/             # Platform service logs
├── scripts/                  # Installation scripts
│   ├── 01-setup-directories.sh # Create directory structure
│   ├── 02-configure-volumes.sh # Configure Nomad volumes
│   ├── 03-deploy-consul.sh   # Deploy Consul
│   ├── 04-deploy-traefik.sh  # Deploy Traefik
│   ├── 05-deploy-vault.sh    # Deploy Vault
│   ├── 06-deploy-registry.sh # Deploy Docker Registry
│   ├── 07-deploy-monitoring.sh # Deploy monitoring stack
│   ├── 08-deploy-logging.sh  # Deploy logging stack
│   ├── 09-deploy-oidc.sh     # Deploy OIDC authentication
│   ├── 10-deploy-homepage.sh # Deploy Homepage dashboard
│   ├── 11-configure-hosts.sh # Configure host file entries
│   ├── 12-create-summary.sh  # Create installation summary
│   ├── pre-backup.sh         # Pre-backup script
│   └── post-backup.sh        # Post-backup script
├── dns-resolver.sh           # Helper script for DNS resolution
├── install.sh                # Main installation script
├── LICENSE                   # License file
├── README.md                 # Project overview and documentation
└── uninstall.sh              # Uninstallation script
```

## Key Files and Their Purpose

### Main Scripts

- **install.sh**: The main entry point for installation. Orchestrates the execution of all module scripts for Stage 1 deployment.
- **uninstall.sh**: Removes all components and cleans up resources.
- **dns-resolver.sh**: Helper script that provides DNS resolution information for environments where hosts file can't be modified.

### Configuration Files

- **default.conf**: Contains default values for all configuration variables. Do not modify this file directly.
- **custom.conf**: User-created file for customizing configuration variables, overriding defaults.
- **volumes.hcl**: Nomad volume definitions, generated during installation.
- **vault_credentials.conf**: Contains Vault credentials, generated during installation.
- **homelab.crt/homelab.key**: Self-signed certificates for secure communication.
- **oidc/clients.json**: OIDC client configurations for various services.

### Job Definitions

All files in the `jobs/` directory are Nomad job definition files (HCL format) that describe how each service should be deployed:

- **consul.hcl**: Service discovery and key-value store.
- **traefik.hcl**: Reverse proxy for all web services with TLS termination.
- **vault.hcl**: Secrets management and credential storage.
- **registry.hcl**: Docker container registry.
- **prometheus.hcl**: Metrics collection.
- **grafana.hcl**: Metrics visualization dashboard.
- **loki.hcl**: Log aggregation service.
- **promtail.hcl**: Log collection agent.
- **keycloak.hcl**: OIDC identity provider.
- **oidc-proxy.hcl**: Forward authentication proxy for OIDC.
- **homepage.hcl**: Central service dashboard and launcher.

### Module Scripts

The `scripts/` directory contains modular installation scripts that are executed in sequence:

1. **01-setup-directories.sh**: Creates the required directory structure on Synology volumes.
2. **02-configure-volumes.sh**: Sets up Nomad volumes for data persistence with storage classes.
3. **03-deploy-consul.sh**: Deploys Consul for service discovery.
4. **04-deploy-traefik.sh**: Deploys Traefik for reverse proxy with self-signed certificates.
5. **05-deploy-vault.sh**: Deploys Vault for secrets management.
6. **06-deploy-registry.sh**: Deploys Docker Registry.
7. **07-deploy-monitoring.sh**: Deploys Prometheus and Grafana.
8. **08-deploy-logging.sh**: Deploys Loki and Promtail.
9. **09-deploy-oidc.sh**: Deploys Keycloak and OIDC authentication.
10. **10-deploy-homepage.sh**: Deploys the Homepage dashboard.
11. **11-configure-hosts.sh**: Sets up local host entries.
12. **12-create-summary.sh**: Generates a summary of the installation.

Additional utility scripts:
- **pre-backup.sh**: Prepares the system for backup by stopping sensitive services.
- **post-backup.sh**: Restarts services after backup completion.

### Documentation

The `docs/` directory contains comprehensive documentation for each component:

- **00-prerequisites.md**: Stage 0 prerequisites and setup
- Component-specific docs (e.g., `01-setup-directories.md`)
- **architecture-diagram.md**: Visual representation of the system architecture
- **backup-recovery.md**: Procedures for backing up and restoring the platform
- **synology-considerations.md**: Specific considerations for Synology DS923+
- **self-signed-certificates.md**: Managing certificates for the platform
- **storage-configuration.md**: Storage class configuration and management
- **troubleshooting.md**: Common issues and their solutions
- **extending-the-platform.md**: Guidelines for extending the platform

## Data Storage

All persistent data is stored in the volume directories:

### Volume 1 (/volume1/docker/nomad/):

- **volumes/high_performance/**: For services requiring fast I/O
  - consul_data/
  - vault_data/
  - prometheus_data/
- **volumes/high_capacity/**: For services requiring larger storage
  - loki_data/
  - registry_data/
- **volumes/standard/**: For general purpose storage
  - grafana_data/
  - keycloak_data/
  - homepage_data/
- **config/**: Configuration files and certificates
- **jobs/**: Generated job definitions

### Volume 2 (/volume2/):

- **backups/**: Backup storage location
  - system/: System-level backups
  - services/: Service-specific backups
- **datasets/**: User data storage

## Logging

- **logs/install.log**: Detailed installation log with timestamps
- **logs/platform/**: Platform-specific logs
  - backup.log: Backup operation logs
  - service-specific logs
- Container logs are collected by Promtail and stored in Loki
- Individual service logs can be accessed via Nomad UI or CLI

## Customization Points

The platform is designed to be customizable at several points:

1. **config/custom.conf**: Override any default configuration variable
2. **jobs/*.hcl**: Modify job definitions for specific requirements
3. **config/oidc/clients.json**: Customize OIDC client configurations
4. **scripts/10-deploy-homepage.sh**: Modify the Homepage dashboard configuration

## Flow of Execution

The deployment process is divided into stages:

### Stage 0 (Manual Setup)
- Install Synology DSM and required packages
- Configure storage and networking
- Install Nomad and Container Manager
- Set up directory structure

### Stage 1 (Automated Deployment via install.sh)
1. The main `install.sh` script checks prerequisites
2. It loads configuration from `default.conf` and (optionally) `custom.conf`
3. It executes each module script in sequence
4. Each script configures and deploys its respective component
5. The final summary script creates a detailed report

## Service Dependency Chain

The platform components have the following dependency chain:

1. Consul (for service discovery)
2. Traefik (for routing)
3. Vault (for secrets management)
4. Keycloak (for authentication)
5. Registry (for container images)
6. Monitoring stack (Prometheus, Grafana)
7. Logging stack (Loki, Promtail)
8. Homepage (for service dashboard)

This dependency ordering is reflected in the script execution sequence.

## Synology-Specific Considerations

The platform is specifically adapted for Synology DS923+ with:

1. **Storage Organization**: Using storage classes on RAID10 volume
2. **Container Manager Integration**: Working with Synology's container management
3. **Resource Allocation**: Optimized for 32GB RAM configuration
4. **Backup Integration**: Working with Synology's Hyper Backup
5. **DNS Integration**: Consul DNS integration with Synology's DNS service
6. **Security**: Self-signed certificates for internal TLS

## Security Architecture

The platform implements a layered security approach:

1. **Network Security**: TLS for all services via self-signed certificates
2. **Authentication**: OIDC for central identity management
3. **Authorization**: Role-based access control 
4. **Secrets Management**: Vault for secure credential storage
5. **Encryption**: Data encryption for sensitive information

## Configuration Management

Configuration is managed through:

1. **Static Configuration**: Files in the `config/` directory
2. **Dynamic Configuration**: Consul key-value store
3. **Secrets**: Vault for sensitive configuration
4. **Service-Specific**: Each service's own configuration

## Extending the Platform

To extend the platform with new services:

1. Create a deployment script in `scripts/` following the naming convention
2. Define a job in `jobs/` for the new service
3. Update documentation to reflect the new component
4. Register the service with Consul for discovery
5. Add appropriate OIDC configuration if authentication is needed
6. Configure Traefik routing rules
7. Add Homepage dashboard metadata

## Networking

The platform sets up the following network infrastructure:

1. **Internal Network**: Service-to-service communication via Consul
2. **External Access**: Traefik as the entry point for all services
3. **DNS Resolution**: Consul DNS for service discovery
4. **TLS Termination**: Self-signed certificates via Traefik
5. **URLs**: Standardized URL scheme (service-name.homelab.local)