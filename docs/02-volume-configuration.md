# Volume Configuration for Synology DS923+

This document provides detailed information about the Nomad volume configuration for the HomeLab DevOps Platform on Synology DS923+.

## Overview

Nomad volumes are used to provide persistent storage for the platform's containerized services. The `02-configure-volumes.sh` script is responsible for creating and registering these volumes with Nomad.

## Nomad Volumes Concept

In Nomad, volumes allow tasks to use persistent storage that exists beyond the lifecycle of a single allocation. This is crucial for services that need to maintain state, such as service discovery, logging, and monitoring.

The HomeLab DevOps Platform uses directories on the Synology filesystem mapped to container paths. This ensures that data is persisted even when containers are restarted or relocated.

## Synology-Specific Volume Considerations

When using Nomad on Synology DS923+, there are specific considerations regarding volume handling:

### Host Volume Type Limitations

The Synology version of Nomad does not support the `host` volume type directly through the `nomad volume create` command. Instead, volumes should be managed through Docker volume mounts in the job definitions.

#### Alternative Volume Approach

Rather than using Nomad's volume plugin system, use the Docker volume mount syntax in your job definitions:

```hcl
job "consul" {
  // ...
  group "consul" {
    task "consul" {
      config {
        // ...
        volumes = [
          "/volume1/docker/nomad/volumes/consul_data:/consul/data"
        ]
      }
    }
  }
}
```

This approach achieves the same goal of persistent storage while working within Synology Nomad's limitations.

## Storage Classes

The platform implements three storage classes to optimize performance and capacity:

| Storage Class | Purpose | Use Cases |
|---------------|---------|-----------|
| high_performance | Fast, frequent access data | Databases, metrics, configuration |
| high_capacity | Large volume, less frequent access | Logs, backups, large datasets |
| standard | General purpose | Configuration, small datasets |

These storage classes are all physically located on your RAID10 array, but the logical separation helps with organization and potential future optimization.

## Volume Types

The platform configures the following volumes:

| Volume Name | Storage Class | Container Mount Path | Purpose |
|-------------|---------------|---------------------|---------|
| consul_data | high_performance | /consul/data | Consul state and data |
| registry_data | high_capacity | /var/lib/registry | Docker Registry images |
| prometheus_data | high_performance | /prometheus | Prometheus time-series data |
| grafana_data | standard | /var/lib/grafana | Grafana dashboards and settings |
| loki_data | high_capacity | /loki | Loki log data |
| vault_data | high_performance | /vault/data | Vault secrets and storage |
| keycloak_data | standard | /opt/keycloak/data | Keycloak user database |
| homepage_data | standard | /app/config | Homepage dashboard configuration |

## Volume Directory Structure

While the Synology Nomad doesn't support volume registration, the script still creates the proper directory structure to be used with Docker volume mounts:

```
/volume1/docker/nomad/volumes/
  ├── high_performance/
  ├── high_capacity/
  ├── standard/
  ├── consul_data/
  ├── vault_data/
  ├── registry_data/
  ├── prometheus_data/
  ├── grafana_data/
  ├── loki_data/
  ├── postgres_data/
  ├── keycloak_data/
  ├── homepage_data/
  └── certificates/
```

## Technical Implementation

The `02-configure-volumes.sh` script:

1. Creates the directories for all storage classes and service volumes
2. Detects that Synology Nomad doesn't support host volumes
3. Creates a VOLUME_README.md file with instructions for using Docker volume mounts
4. Ensures all directories have proper permissions

## Volume Usage in Jobs

For Synology Nomad installations, volumes are used with the following syntax:

```hcl
job "vault" {
  // Job configuration...

  group "vault" {
    task "vault" {
      // Task configuration...

      config {
        image = "vault:1.9.0"
        
        volumes = [
          "/volume1/docker/nomad/volumes/vault_data:/vault/data"
        ]
      }
      
      // Rest of the task definition...
    }
  }
}
```

This directly maps the host directory to the container path without requiring Nomad volume registration.

## Volume Persistence on Synology

Volumes persist data across:

- Container restarts
- Nomad job updates
- Nomad client restarts
- System reboots
- DSM updates (though services will restart)

However, volumes do NOT automatically persist across:

- Manual deletion of the data directory
- Migration to a different Synology device

Always back up important data before performing major changes to your system.

## Synology RAID Considerations

Your Synology DS923+ with 4x4TB drives in RAID10:

- Provides approximately 8TB of usable storage
- Offers good read/write performance for all service types
- Provides redundancy (can survive a single drive failure)

All storage classes (high_performance, high_capacity, standard) in this configuration are on the same physical RAID array, but the logical separation helps with organization and management.

## Customizing Volumes

You can customize volume locations by modifying the `DATA_DIR` variable in `custom.conf`. This will affect all volumes.

If you need to customize individual volume locations, you'll need to modify both:

1. The directory creation paths in `01-setup-directories.sh`
2. The corresponding volume mount paths in your job definitions

## Performance Considerations on Synology

For optimal performance on your Synology DS923+:

- Prometheus and databases will benefit from the high_performance storage class
- Large logs and image repositories should use high_capacity
- Consider enabling SSD cache in DSM if available for frequently accessed data
- Monitor disk I/O using Synology Resource Monitor
- Adjust service resource limits if I/O becomes a bottleneck

## Docker Images on Synology

It's important to note that Docker images and container runtime data are stored in Synology's Container Manager location (`/var/packages/ContainerManager/var/docker`), not in your Nomad volumes. This location cannot be easily changed without breaking Container Manager.

Your Nomad volumes are only for the persistent data generated and used by the services, not for the container images themselves.

## Troubleshooting Volume Issues

Common volume-related issues and solutions:

1. **"Error unknown volume type" When Creating Volumes**:
   - **Cause**: The Synology version of Nomad does not support the host volume plugin.
   - **Solution**: Use Docker volume mounts directly in your job definitions rather than trying to register volumes with Nomad.

2. **Data Not Persisting**:
   - Verify the volume mount path in the job definition is correct
   - Check that the host directory exists with proper permissions
   - Ensure the container is writing to the mounted path

3. **Permission Issues**:
   - Verify container user has access to the mounted directory
   - Check if ownership is set correctly on the host: `sudo chown -R <uid>:<gid> $DATA_DIR/<volume-name>`
   - Ensure that the required permissions are applied to the volume

4. **Cannot Access Volume Data**:
   - Check if the directory exists: `ls -la $DATA_DIR/<volume-name>`
   - Verify the path in your job definition
   - Check for typos in the volume mount path

## Next Steps

After configuring volumes, the next step is to deploy Consul for service discovery. This is covered in [Consul Setup](03-consul-setup.md).
