# Directory Setup for Synology DS923+

This document provides detailed information about the directory structure setup of the HomeLab DevOps Platform on Synology DS923+.

## Overview

The platform requires a specific directory structure to function properly. These directories store configuration files, job definitions, and persistent data for the various services. The `01-setup-directories.sh` script handles the creation of all necessary directories.

## Directory Structure

### Base Directories

- **config/**: Contains configuration files for the platform
  - **default.conf**: Default configuration variables
  - **custom.conf**: Custom configuration overrides (optional)
  - Generated credentials and configuration files

- **jobs/**: Contains Nomad job definitions for all services
  - Generated during installation, one file per service

- **logs/**: Contains installation and operation logs
  - **install.log**: Log file from the installation process
  - **platform/**: Application and service-specific logs

- **scripts/**: Contains modular installation scripts
  - One script per platform component

- **docs/**: Contains documentation files

### Data Directories

The base data directory (default: `/volume1/docker/nomad/volumes`) contains subdirectories for each service and storage class:

#### Storage Classes
- **high_performance/**: For services requiring fast I/O (databases, metrics)
- **high_capacity/**: For services requiring large storage (logs, backups)
- **standard/**: For general purpose storage

#### Service Directories
- **consul_data/**: Consul data
- **registry_data/**: Docker Registry images
- **prometheus_data/**: Prometheus time-series data
- **grafana_data/**: Grafana dashboards and settings
- **loki_data/**: Loki log data
- **vault_data/**: Vault storage data
- **keycloak_data/**: Keycloak user data and configuration
- **homepage_data/**: Homepage dashboard configuration

## Directory Permissions for Synology

Directory permissions are crucial for proper operation on Synology DSM:

| Directory | Owner | Permissions | Notes |
|-----------|-------|-------------|-------|
| consul_data | your-username:users | 777 | Consul runs as a generic user in container |
| registry_data | your-username:users | 755 | Registry needs write access |
| prometheus_data | your-username:users | 755 | Prometheus needs write access |
| grafana_data | 472:472 | 755 | Grafana runs as UID 472 |
| loki_data | your-username:users | 755 | Loki needs write access |
| vault_data | your-username:users | 755 | Vault needs secure access |
| keycloak_data | your-username:users | 755 | Keycloak data storage |
| homepage_data | your-username:users | 755 | Homepage configuration data |

## Customizing Directory Locations

You can customize directory locations by modifying the following variables in `custom.conf`:

```bash
# Base directories
DATA_DIR="/volume1/docker/nomad/volumes"
CONFIG_DIR="/volume1/docker/nomad/config"
JOB_DIR="/volume1/docker/nomad/jobs"
LOG_DIR="/volume1/logs"
```

This is particularly useful when:
- You want to place data on a different volume
- You want to use a storage class for specific services
- You're customizing the directory structure

## Technical Implementation

The directory setup is handled by the `01-setup-directories.sh` script, which:

1. Creates the base directories if they don't exist
2. Creates the data subdirectories
3. Sets appropriate permissions for each directory
4. Ensures proper ownership for container-specific requirements

Here's how the script creates the directories:

```bash
# Create config directory if it doesn't exist
mkdir -p $CONFIG_DIR
mkdir -p $JOB_DIR
mkdir -p $LOG_DIR/platform

# Create volume directories for storage classes
mkdir -p $DATA_DIR/high_performance
mkdir -p $DATA_DIR/high_capacity
mkdir -p $DATA_DIR/standard

# Create service data directories
mkdir -p $DATA_DIR/consul_data
mkdir -p $DATA_DIR/registry_data
mkdir -p $DATA_DIR/prometheus_data
mkdir -p $DATA_DIR/grafana_data
mkdir -p $DATA_DIR/loki_data
mkdir -p $DATA_DIR/vault_data
mkdir -p $DATA_DIR/keycloak_data
mkdir -p $DATA_DIR/homepage_data

# Set appropriate permissions
chmod -R 755 $DATA_DIR
chmod 777 $DATA_DIR/consul_data
chown -R 472:472 $DATA_DIR/grafana_data
```

## Storage Requirements on Synology RAID10

Consider these approximate storage requirements when planning your installation on your Synology DS923+ with RAID10:

| Directory | Minimum Size | Recommended Size | Notes |
|-----------|--------------|------------------|-------|
| consul_data | 50MB | 100MB | Grows with service count |
| registry_data | 100MB | 10GB | Depends on image count |
| prometheus_data | 1GB | 5GB | Depends on retention period |
| grafana_data | 50MB | 500MB | For dashboards and plugins |
| loki_data | 1GB | 10GB | Depends on log volume |
| vault_data | 50MB | 200MB | For secrets and authentication |
| keycloak_data | 100MB | 1GB | User database and configuration |
| homepage_data | 50MB | 100MB | Dashboard configuration |

These figures assume a typical homelab setup. Adjust based on your specific needs.

## Synology Volume Considerations

When using Synology volumes:

1. **Performance**: The RAID10 configuration provides good performance for all services
2. **Storage Classes**: 
   - Use `high_performance/` for Prometheus, Vault, Consul
   - Use `high_capacity/` for Loki logs, Registry images
   - Use `standard/` for configuration data and smaller services

3. **Container Manager**: All Docker images and container runtime data are stored in `/var/packages/ContainerManager/var/docker` on the system volume, not in your directories.

## Backup Considerations

When backing up the platform, you should include:

1. The entire data directory (`$DATA_DIR`)
2. Configuration files (`$CONFIG_DIR`)
3. Custom job definitions (`$JOB_DIR`)

The setup allows for easy backup of all persistent data by simply archiving these directories. See [Backup and Recovery](backup-recovery.md) for detailed procedures.

## Synology DSM Updates

During DSM updates, your data directories should remain intact, but container services will be restarted. It's recommended to:

1. Perform a backup before DSM updates
2. Check directory permissions after major DSM updates
3. Verify service operation after updates complete

## Troubleshooting Directory Issues

Common directory-related issues and solutions:

1. **Permission Denied Errors**:
   - Verify directory ownership with `ls -la $DATA_DIR`
   - Fix permissions with `chmod -R 755 $DATA_DIR`
   - Ensure correct user ownership with `chown -R <user>:<group> $DATA_DIR/<service>_data`

2. **Disk Space Issues**:
   - Check available space with `df -h $DATA_DIR`
   - Clean up unnecessary data
   - Consider moving the data directory to a larger volume

3. **Cannot Create Directory**:
   - Ensure parent directories exist
   - Check filesystem mount permissions
   - Verify you have sudo access

4. **Data Persistence Issues**:
   - Confirm volume mounts are correct in Nomad job definitions
   - Verify data is written to the correct location
   - Check if container is using the correct host path

## Next Steps

After setting up the directories, the next step is to configure Nomad volumes. This is covered in [Volume Configuration](02-volume-configuration.md).