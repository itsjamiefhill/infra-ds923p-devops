# Volume Configuration for Synology DS923+

This document provides detailed information about the Nomad volume configuration for the HomeLab DevOps Platform on Synology DS923+.

## Overview

Nomad volumes are used to provide persistent storage for the platform's containerized services. The `02-configure-volumes.sh` script is responsible for creating and registering these volumes with Nomad.

## Nomad Volumes Concept

In Nomad, volumes allow tasks to use persistent storage that exists beyond the lifecycle of a single allocation. This is crucial for services that need to maintain state, such as service discovery, logging, and monitoring.

The HomeLab DevOps Platform uses Nomad's "host" volume type, which maps directories on the Synology filesystem to container paths. This ensures that data is persisted even when containers are restarted or relocated.

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

## Volume Configuration File

Volumes are defined in HCL format in the `config/volumes.hcl` file, which is generated during installation. Here's what this file contains:

```hcl
# Storage class volumes
volume "high_performance" {
  type = "host"
  config {
    source = "/volume1/nomad/volumes/high_performance"
  }
}

volume "high_capacity" {
  type = "host"
  config {
    source = "/volume1/nomad/volumes/high_capacity"
  }
}

volume "standard" {
  type = "host"
  config {
    source = "/volume1/nomad/volumes/standard"
  }
}

# Service-specific volumes
volume "consul_data" {
  type = "host"
  config {
    source = "/volume1/nomad/volumes/consul_data"
  }
}

// Additional volumes following the same pattern...
```

## Technical Implementation

The `02-configure-volumes.sh` script:

1. Creates the volumes.hcl configuration file based on the configured `DATA_DIR`
2. Registers the volumes with Nomad using the `nomad volume create` command
3. Verifies that volumes are successfully created

Here's how volumes are registered with Nomad:

```bash
nomad volume create $CONFIG_DIR/volumes.hcl
```

## Volume Usage in Jobs

Once volumes are created, they are referenced in Nomad job definitions. For example, here's how Vault uses its volume:

```hcl
job "vault" {
  // Job configuration...

  group "vault" {
    volume "vault_data" {
      type = "host"
      read_only = false
      source = "vault_data"
    }

    task "vault" {
      // Task configuration...

      volume_mount {
        volume = "vault_data"
        destination = "/vault/data"
        read_only = false
      }
      
      // Rest of the task definition...
    }
  }
}
```

Each job that requires persistent storage:

1. References a volume by name in its group definition
2. Mounts that volume to the appropriate path within the container
3. Configures read/write permissions as needed

## Volume Persistence on Synology

Volumes persist data across:

- Container restarts
- Nomad job updates
- Nomad client restarts
- System reboots
- DSM updates (though services will restart)

However, volumes do NOT automatically persist across:

- Nomad volume deletions
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

1. The generated `volumes.hcl` file
2. The corresponding data directory location

## Volume Management Commands

Useful Nomad commands for managing volumes:

- **List all volumes**: `nomad volume list`
- **Show volume details**: `nomad volume status <volume-name>`
- **Delete a volume**: `nomad volume delete <volume-name>`

Note that deleting a volume in Nomad doesn't delete the actual data on disk. It only removes Nomad's reference to it.

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

1. **Volume Creation Failures**:
   - Check Nomad server logs: `cat /volume1/logs/platform/nomad.log`
   - Verify directory permissions: `ls -la $DATA_DIR`
   - Ensure Nomad has permission to access the host directories

2. **Data Not Persisting**:
   - Verify volume is correctly registered: `nomad volume status <volume-name>`
   - Check that the job definition includes the correct volume references
   - Ensure the task's `volume_mount` points to the correct destination

3. **Permission Issues**:
   - Verify container user has access to the mounted directory
   - Check if ownership is set correctly on the host: `sudo chown -R <uid>:<gid> $DATA_DIR/<volume-name>`
   - Ensure that the required permissions are applied to the volume

4. **"Volume Not Found" Errors**:
   - Verify the volume exists in Nomad: `nomad volume list`
   - Check that the volume name in the job matches the registered volume name
   - Ensure you're operating in the correct Nomad namespace (if applicable)

## Next Steps

After configuring volumes, the next step is to deploy Consul for service discovery. This is covered in [Consul Setup](03-consul-setup.md).