# Volume Configuration for Synology DS923+

This document provides detailed information about the volume configuration for the HomeLab DevOps Platform on Synology DS923+.

## Overview

Persistent storage is essential for containerized services in the platform. The `02-configure-volumes.sh` script creates the necessary directory structure and provides templates for using mount directives in Nomad job configurations.

## Volume Configuration Approaches

There are two main approaches for configuring persistent storage with Nomad on Synology:

1. **Using the `mount` directive** (Recommended)
2. **Using Docker volume mounts** (Alternative)

The platform automatically determines which approach to use based on your Nomad installation capabilities.

## Mount Directive Approach

The recommended approach for Synology Nomad installations is to use the `mount` directive in your job configurations:

```hcl
job "consul" {
  // ...
  group "consul" {
    task "consul" {
      driver = "docker"
      
      config {
        image = "hashicorp/consul:latest"
        
        mount {
          type = "bind"
          source = "/volume1/docker/nomad/volumes/consul_data"
          target = "/consul/data"
          readonly = false
        }
      }
    }
  }
}
```

This approach:
- Uses Nomad's native configuration syntax
- Provides clearer semantics in job definitions
- Follows Nomad best practices
- Is compatible with Synology's Nomad implementation

### Mount Directive Options

The `mount` directive supports several options:

| Option | Description | Example |
|--------|-------------|---------|
| `type` | The mount type (usually "bind") | `type = "bind"` |
| `source` | The path on the host system | `source = "/volume1/docker/nomad/volumes/consul_data"` |
| `target` | The path inside the container | `target = "/consul/data"` |
| `readonly` | Whether the mount is read-only | `readonly = false` |

## Docker Volume Mount Approach (Alternative)

If you encounter issues with the `mount` directive, you can also use Docker's volume syntax:

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

This approach still works but is considered Docker-specific rather than using Nomad's native configuration.

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

The script creates the following directory structure to be used with mount directives:

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

1. Checks if your Nomad installation supports host volumes
2. If host volumes are supported, creates traditional Nomad volume definitions
3. For Synology systems, creates job templates that use the `mount` directive
4. Generates a comprehensive VOLUME_README.md with usage instructions
5. Creates example templates for all major services

## Volume Templates

The script generates volume templates for all major services in `config/volume_templates/`:

- consul.hcl
- vault.hcl
- traefik.hcl
- prometheus.hcl
- grafana.hcl
- registry.hcl
- loki.hcl
- keycloak.hcl
- homepage.hcl

These templates show the proper way to implement the mount directive for each service.

## Using Volume Templates

To use the templates in your job definitions:

1. Refer to the templates in `config/volume_templates/`
2. Copy the mount directive block to your job definition
3. Adjust paths and options as needed

For example:

```hcl
job "prometheus" {
  group "prometheus" {
    task "prometheus" {
      driver = "docker"
      
      config {
        image = "prom/prometheus:latest"
        
        mount {
          type = "bind"
          source = "/volume1/docker/nomad/volumes/prometheus_data"
          target = "/prometheus"
          readonly = false
        }
        
        mount {
          type = "bind"
          source = "/volume1/docker/nomad/config/prometheus/prometheus.yml"
          target = "/etc/prometheus/prometheus.yml"
          readonly = true
        }
      }
    }
  }
}
```

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
2. The corresponding mount source paths in your job definitions

## Performance Considerations on Synology

For optimal performance on your Synology DS923+:

- Prometheus and databases will benefit from the high_performance storage class
- Large logs and image repositories should use high_capacity
- Consider enabling SSD cache in DSM if available for frequently accessed data
- Monitor disk I/O using Synology Resource Monitor
- Adjust service resource limits if I/O becomes a bottleneck

## Docker Images on Synology

It's important to note that Docker images and container runtime data are stored in Synology's Container Manager location (`/var/packages/ContainerManager/var/docker`), not in your volume mounts. This location cannot be easily changed without breaking Container Manager.

Your mounted directories are only for the persistent data generated and used by the services, not for the container images themselves.

## Multiple Mount Points

Some services may require multiple mount points. For example, Traefik needs access to both certificates and configuration:

```hcl
config {
  image = "traefik:latest"
  
  mount {
    type = "bind"
    source = "/volume1/docker/nomad/volumes/certificates"
    target = "/certs"
    readonly = true
  }
  
  mount {
    type = "bind"
    source = "/volume1/docker/nomad/config/traefik"
    target = "/etc/traefik"
    readonly = true
  }
}
```

You can define as many mount directives as needed for a service.

## Troubleshooting Volume Issues

Common volume-related issues and solutions:

1. **Mount Directive Not Working**:
   - **Solution**: Try the alternative `volumes = []` syntax
   - Verify Docker driver is being used
   - Check for typos in paths

2. **Data Not Persisting**:
   - Verify the mount path in the job definition is correct
   - Check that the host directory exists with proper permissions
   - Ensure the container is writing to the mounted path

3. **Permission Issues**:
   - Verify container user has access to the mounted directory
   - Check if ownership is set correctly on the host: `sudo chown -R <uid>:<gid> $DATA_DIR/<volume-name>`
   - Ensure that the required permissions are applied to the volume

4. **Cannot Access Volume Data**:
   - Check if the directory exists: `ls -la $DATA_DIR/<volume-name>`
   - Verify the path in your job definition
   - Check for typos in the mount source or target paths

## Next Steps

After configuring volumes, the next step is to deploy Consul for service discovery. This is covered in [Consul Setup](03-consul-setup.md).