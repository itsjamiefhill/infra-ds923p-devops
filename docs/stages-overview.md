# Stages Overview for HomeLab DevOps Platform

This document provides an overview of the different stages involved in setting up and maintaining the HomeLab DevOps Platform on Synology DS923+.

## Table of Contents

1. [Introduction](#introduction)
2. [Stage 0: Prerequisites and Manual Setup](#stage-0-prerequisites-and-manual-setup)
3. [Stage 1: Core Platform Deployment](#stage-1-core-platform-deployment)
4. [Stage 2: Application Deployment](#stage-2-application-deployment)
5. [Stage 3: Continuous Improvement](#stage-3-continuous-improvement)
6. [Stage Transitions](#stage-transitions)
7. [Rollback Procedures](#rollback-procedures)

## Introduction

The HomeLab DevOps Platform implementation follows a staged approach to ensure a systematic, reliable deployment process. Each stage builds upon the previous one, creating a solid foundation for your homelab environment.

These stages are designed to:
- Break down the complex setup into manageable phases
- Allow for testing and validation at each step
- Provide clear boundaries between different layers of the platform
- Establish a path for future growth and expansion

## Stage 0: Prerequisites and Manual Setup

Stage 0 consists of the initial, one-time manual setup of the Synology hardware and core software requirements.

### Objectives
- Configure Synology DS923+ hardware
- Set up DSM operating system
- Configure network settings
- Install required packages
- Prepare storage volumes
- Install Nomad

### Key Tasks

1. **Hardware Setup**
   - Install 32GB RAM
   - Configure 4x 4TB HDDs in RAID10
   - Connect to network

2. **DSM Configuration**
   - Install and update DSM to latest version
   - Configure static IP (10.0.4.10 or your preferred IP)
   - Enable SSH
   - Configure firewall settings
   - Set up user accounts

3. **Package Installation**
   - Install Container Manager from Package Center
   - Install Text Editor from Package Center
   - Install Hyper Backup from Package Center (for backups)

4. **Storage Configuration**
   - Create storage pool with RAID10
   - Create volume1 (devops) and volume2 (data)
   - Set up shared folders

5. **Nomad Installation**
   - Install Nomad SPK package
   - Verify Nomad is running
   - Access Nomad UI (http://synology-ip:4646)
   - Create management token

### Completion Criteria
- Synology hardware is properly configured
- DSM is up-to-date and secured
- Network is properly configured
- Storage is set up with appropriate volumes
- Nomad is installed and accessible
- Directory structure is prepared

### Documentation
- [Prerequisites and Stage 0 Setup](00-prerequisites.md)
- [Stage 0 Manual Configuration](stage0-manual-config.md)

## Stage 1: Core Platform Deployment

Stage 1 involves the automated deployment of the core DevOps platform components using scripts.

### Objectives
- Deploy service discovery (Consul)
- Set up reverse proxy (Traefik)
- Configure secrets management (Vault)
- Implement container registry
- Deploy monitoring stack
- Implement logging stack
- Set up authentication
- Deploy central dashboard

### Key Tasks

1. **Base Setup**
   - Set up directories and volumes
   - Create certificates
   - Configure Nomad volumes

2. **Core Services Deployment**
   - Deploy Consul for service discovery
   - Deploy Traefik for reverse proxy
   - Deploy Vault for secrets management
   - Deploy Docker Registry

3. **Monitoring and Logging**
   - Deploy Prometheus for metrics
   - Deploy Grafana for visualization
   - Deploy Loki for log storage
   - Deploy Promtail for log collection

4. **Authentication and Dashboard**
   - Deploy Keycloak for OIDC
   - Configure OIDC proxy
   - Deploy Homepage dashboard
   - Configure host entries

### Execution
The platform is deployed using the main installation script:
```bash
./install.sh
```

This script orchestrates the execution of module scripts in the correct order:
1. `01-setup-directories.sh`
2. `02-configure-volumes.sh`
3. `03-deploy-consul.sh`
...through to...
12. `12-create-summary.sh`

### Completion Criteria
- All core services deployed and running
- Services discoverable via Consul
- TLS working with self-signed certificates
- Authentication functional
- Monitoring and logging operational
- Dashboard accessible showing all services

### Documentation
The entire `docs/` directory, with particular focus on:
- [Setup Directories](01-setup-directories.md)
- [Consul Setup](03-consul-setup.md)
- [Traefik Setup](04-traefik-setup.md)
- [Vault Setup](05-vault-setup.md)
- [Monitoring Setup](07-monitoring-setup.md)
- [OIDC Setup](09-oidc-setup.md)
- [Homepage Setup](10-homepage-setup.md)

## Stage 2: Application Deployment

Stage 2 builds upon the core platform to deploy actual applications and services.

### Objectives
- Deploy containerized applications
- Integrate applications with platform services
- Implement CI/CD pipelines
- Set up development environments

### Key Tasks

1. **Application Deployment**
   - Define application Nomad jobs
   - Configure application storage
   - Set up application secrets in Vault
   - Configure Traefik routes

2. **CI/CD Implementation**
   - Set up CI server (e.g., Jenkins, GitLab Runner)
   - Configure build pipelines
   - Implement automated testing
   - Set up deployment pipelines

3. **Development Environment**
   - Create development configurations
   - Set up local development tools
   - Configure IDE integrations
   - Implement development workflows

### Execution
Applications are deployed using individual deployment scripts or through CI/CD pipelines:
```bash
./deploy-app.sh <app-name>
```

Or via CI/CD triggered deployments.

### Completion Criteria
- Applications deployed and running
- Applications integrated with platform services
- CI/CD pipelines operational
- Development environments configured

### Documentation
- Application-specific documentation
- CI/CD pipeline documentation
- Development workflow documentation

## Stage 3: Continuous Improvement

Stage 3 is the ongoing maintenance and improvement of the platform and applications.

### Objectives
- Monitor and maintain platform health
- Implement improvements and upgrades
- Optimize resource usage
- Enhance security

### Key Tasks

1. **Monitoring and Maintenance**
   - Regular health checks
   - Performance monitoring
   - Capacity planning
   - Backup verification

2. **Upgrades and Improvements**
   - Component upgrades
   - Feature enhancements
   - Security patches
   - Performance optimizations

3. **Documentation and Knowledge Base**
   - Keep documentation updated
   - Document procedures and solutions
   - Build knowledge base
   - Improve automation

### Execution
Continuous improvement tasks are performed through a combination of automated and manual processes:
```bash
./upgrade-component.sh <component-name>
```

### Completion Criteria
Continuous improvement is an ongoing process without a specific completion point, but regular reviews should evaluate:
- System stability and performance
- Security posture
- Resource utilization
- Documentation quality

## Stage Transitions

### From Stage 0 to Stage 1
- Verify all Stage 0 prerequisites are met
- Run the main installation script (`install.sh`)
- Validate core platform functionality
- Complete all post-installation tasks (e.g., unsealing Vault)

### From Stage 1 to Stage 2
- Ensure all core platform services are running correctly
- Validate integration points (authentication, service discovery, etc.)
- Begin application deployment
- Implement CI/CD pipelines

### From Stage 2 to Stage 3
- Platform and applications are deployed and functional
- Users are onboarded and trained
- Monitoring and alerting are configured
- Begin continuous improvement cycle

## Rollback Procedures

### Stage 1 Rollback
If issues occur during Stage 1 deployment:
```bash
# Stop all platform services
for job in homepage oidc-proxy keycloak loki promtail grafana prometheus registry vault traefik consul; do
  nomad job stop $job
done

# Clean up data directories
rm -rf /volume1/nomad/volumes/*

# Restart from clean slate
./install.sh
```

### Stage 2 Rollback
If issues occur with specific applications:
```bash
# Stop the problematic application
nomad job stop <app-name>

# Clean up application data if needed
rm -rf /volume1/nomad/volumes/<app_data>

# Redeploy the application
nomad job run jobs/<app-name>.hcl
```

### General Snapshot Rollback
For issues that require rolling back to a previous state:
```bash
# Restore from Hyper Backup
# Follow Synology Hyper Backup restoration procedure

# Restart services
for job in consul traefik vault registry prometheus grafana loki promtail keycloak oidc-proxy homepage; do
  nomad job run jobs/$job.hcl
done

# Unseal Vault
nomad alloc exec -task vault <vault-alloc-id> vault operator unseal <key1>
nomad alloc exec -task vault <vault-alloc-id> vault operator unseal <key2>
nomad alloc exec -task vault <vault-alloc-id> vault operator unseal <key3>
```

By following this staged approach, you can systematically build, deploy, and maintain your HomeLab DevOps Platform in a manageable and reliable way.