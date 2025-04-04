# Storage Configuration for Synology DS923+

This document provides detailed information about storage configuration for the HomeLab DevOps Platform on a Synology DS923+.

## Table of Contents

1. [Overview](#overview)
2. [Hardware Configuration](#hardware-configuration)
3. [Platform Implementation Notes](#platform-implementation-notes)
4. [Storage Classes](#storage-classes)
5. [Volume Setup](#volume-setup)
6. [Nomad Volume Configuration](#nomad-volume-configuration)
7. [Service-Specific Storage](#service-specific-storage)
8. [Performance Considerations](#performance-considerations)
9. [Backup Strategies](#backup-strategies)
10. [Monitoring Storage](#monitoring-storage)
11. [Troubleshooting](#troubleshooting)

## Overview

The storage configuration for the HomeLab DevOps Platform on Synology DS923+ involves several layers:

1. **Physical Storage**: 4x 4TB HDDs in RAID10 configuration
2. **Synology Volumes**: Logical volumes created on the storage pool
3. **Nomad Volumes**: Host volumes mapped to service containers
4. **Storage Classes**: Logical grouping of volumes by performance characteristics
5. **Service Data**: Persistent data stored by individual services

This layered approach allows for flexible, efficient, and reliable storage management.

## Hardware Configuration

### Physical Disks

The Synology DS923+ is configured with:
- 4x 4TB HDDs in RAID10 configuration
- Provides approximately 8TB of usable storage
- Offers a balance of performance and redundancy
- Can survive a single disk failure

### RAID Configuration

RAID10 (also called RAID 1+0) combines mirroring and striping:
- Data is striped across multiple mirrored pairs
- Provides both performance (from striping) and redundancy (from mirroring)
- Allows for faster read/write operations compared to RAID5
- Provides better redundancy than RAID0
- Suitable for mixed read/write workloads in a homelab environment

### Optional SSD Cache

For enhanced performance, consider adding SSD cache:
- The DS923+ supports NVMe SSDs for caching
- Read-only cache requires 1 SSD
- Read-write cache requires 2 SSDs (for redundancy)
- Accelerates frequently accessed data
- Particularly beneficial for high_performance storage class

## Platform Implementation Notes

### Synology Nomad Implementation

The Synology implementation of Nomad differs from standard Nomad in several ways:

1. **Volume Plugin Support**: Synology Nomad does not support the standard Nomad volume plugins or the `host` volume type used in the `nomad volume create` command.

2. **Docker Integration**: Volume persistence must be handled through Docker's volume mount system rather than Nomad's volume system.

3. **Directory Mapping**: The platform still creates all the necessary directories as described in this document, but they are mounted directly in job definitions rather than registered with Nomad.

The scripts have been adapted to detect this environment difference and adjust accordingly. If you see a `VOLUME_README.md` file in your config directory, this indicates that your environment is using the alternative approach.

## Storage Classes

The platform uses logical storage classes to organize data based on access patterns and performance requirements:

### 1. high_performance

```
/volume1/docker/nomad/volumes/high_performance/
```

**Purpose**: For services requiring fast I/O and low latency.

**Characteristics**:
- Optimized for read/write performance
- Suitable for frequently accessed data
- Prioritized for SSD caching (if available)

**Recommended Services**:
- Consul (service discovery data)
- Vault (secrets and authentication)
- Prometheus (real-time metrics)

### 2. high_capacity

```
/volume1/docker/nomad/volumes/high_capacity/
```

**Purpose**: For services requiring large storage volumes.

**Characteristics**:
- Optimized for storing large amounts of data
- Suitable for write-intensive workloads
- Less frequently accessed than high_performance

**Recommended Services**:
- Loki (log storage)
- Docker Registry (container images)
- Large datasets

### 3. standard

```
/volume1/docker/nomad/volumes/standard/
```

**Purpose**: General purpose storage for most services.

**Characteristics**:
- Balanced read/write performance
- Moderate access frequency
- Suitable for most service data

**Recommended Services**:
- Grafana (dashboards, users)
- Keycloak (authentication data)
- Homepage (configuration)
- Other services with moderate storage requirements

## Volume Setup

### Synology Volume Creation

1. **Create Storage Pool**:
   - In DSM, go to Storage Manager > Storage Pool
   - Click "Create"
   - Select "Better performance" (RAID10)
   - Select all 4 HDDs
   - Complete the wizard

2. **Create Volumes**:
   - In Storage Manager > Volume
   - Click "Create"
   - Choose your storage pool
   - Allocate space:
     - `volume1` (devops): Approximately 2TB
     - `volume2` (data): Remaining space (approximately 6TB)
   - Choose filesystem (Btrfs recommended)
   - Complete the wizard

### Directory Structure Setup

Create the necessary directory structure:

```bash
# Create main directories
mkdir -p /volume1/docker/nomad/config
mkdir -p /volume1/docker/nomad/jobs
mkdir -p /volume1/logs/platform

# Create storage class directories
mkdir -p /volume1/docker/nomad/volumes/high_performance
mkdir -p /volume1/docker/nomad/volumes/high_capacity
mkdir -p /volume1/docker/nomad/volumes/standard

# Create service-specific directories
mkdir -p /volume1/docker/nomad/volumes/consul_data
mkdir -p /volume1/docker/nomad/volumes/vault_data
mkdir -p /volume1/docker/nomad/volumes/prometheus_data
mkdir -p /volume1/docker/nomad/volumes/grafana_data
mkdir -p /volume1/docker/nomad/volumes/loki_data
mkdir -p /volume1/docker/nomad/volumes/registry_data
mkdir -p /volume1/docker/nomad/volumes/keycloak_data
mkdir -p /volume1/docker/nomad/volumes/homepage_data
mkdir -p /volume1/docker/nomad/volumes/certificates

# Create backup directories
mkdir -p /volume2/backups/system
mkdir -p /volume2/backups/services
mkdir -p /volume2/datasets

# Set permissions
chmod -R 755 /volume1/nomad
chmod -R 755 /volume1/logs
chmod -R 755 /volume2/backups
chmod -R 755 /volume2/datasets

# Set specific permissions for certain services
chmod 777 /volume1/docker/nomad/volumes/consul_data
chown -R 472:472 /volume1/docker/nomad/volumes/grafana_data
```

## Volume Configuration with Docker Mounts

Since Synology Nomad doesn't support the host volume type, persistent storage is configured directly in job definitions using Docker volume mounts:

```hcl
job "vault" {
  // Job configuration...

  group "vault" {
    task "vault" {
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

All necessary directories are still created during installation to ensure they exist with proper permissions before being mounted in containers.

## Updated Volume Usage in Jobs Section:

## Volume Usage in Jobs

Since volumes are not registered with Nomad on Synology, they are referenced in job definitions using Docker volume mounts:

```hcl
job "consul" {
  // Job configuration...

  group "consul" {
    task "consul" {
      // Task configuration...

      config {
        image = "consul:1.11.4"
        
        volumes = [
          "/volume1/docker/nomad/volumes/consul_data:/consul/data"
        ]
      }
      
      // Rest of the task definition...
    }
  }
}

Each job that requires persistent storage:

1. References a volume path directly in its Docker configuration
2. Mounts that volume to the appropriate path within the container
3. Ensures proper permissions are set on the host directory

Be sure to use the correct path mappings as shown in the table below:

Service | Host Path | Container Path
Consul | /volume1/docker/nomad/volumes/consul_data/ | consul/data
Vault | /volume1/docker/nomad/volumes/vault_data/ | vault/data
Prometheus | /volume1/docker/nomad/volumes/prometheus_data | /prometheus
Grafana | /volume1/docker/nomad/volumes/grafana_data/ | var/lib/grafana
Loki | /volume1/docker/nomad/volumes/loki_data/ | loki
Registry | /volume1/docker/nomad/volumes/registry_data | /var/lib/registry
Keycloak | /volume1/docker/nomad/volumes/keycloak_data | /opt/keycloak 
Homepage | /volume1/docker/nomad/volumes/homepage_data | /app/config

## Updated Troubleshooting Section:

## Troubleshooting Volume Issues

1. Common volume-related issues and solutions:

1. **"Error unknown volume type" When Using Nomad Volume Commands**:
   - **Cause**: The Synology version of Nomad does not support the host volume plugin.
   - **Solution**: Use Docker volume mounts directly in your job definitions instead of trying to register volumes with Nomad.
   
   ```hcl
   config {
     volumes = [
       "/volume1/docker/nomad/volumes/service_data:/container/path"
     ]
   }```

2. Data Not Persisting:

Verify the volume mount path in the job definition is correct
Check that the host directory exists with proper permissions
Ensure the container is writing to the mounted path

3. Permission Issues:

Verify container user has access to the mounted directory
Check if ownership is set correctly on the host: sudo chown -R <uid>:<gid> $DATA_DIR/<volume-name>
For services with specific user requirements (like Grafana or PostgreSQL), ensure the UID/GID ownership matches the container's user

## Service-Specific Storage

### Consul

```hcl
job "consul" {
  // ...
  group "consul" {
    volume "consul_data" {
      type = "host"
      read_only = false
      source = "consul_data"
    }
    
    task "consul" {
      // ...
      volume_mount {
        volume = "consul_data"
        destination = "/consul/data"
        read_only = false
      }
    }
  }
}
```

### Prometheus (Using Storage Class)

```hcl
job "prometheus" {
  // ...
  group "monitoring" {
    volume "prometheus_storage" {
      type = "host"
      read_only = false
      source = "high_performance"
    }
    
    task "prometheus" {
      // ...
      volume_mount {
        volume = "prometheus_storage"
        destination = "/prometheus"
        read_only = false
      }
    }
  }
}
```

### Loki (Using Storage Class)

```hcl
job "loki" {
  // ...
  group "logging" {
    volume "loki_storage" {
      type = "host"
      read_only = false
      source = "high_capacity"
    }
    
    task "loki" {
      // ...
      volume_mount {
        volume = "loki_storage"
        destination = "/loki"
        read_only = false
      }
    }
  }
}
```

## Performance Considerations

### Optimizing Storage Performance

1. **Access Patterns**:
   - Place frequently accessed, read-intensive data in `high_performance`
   - Place large, write-intensive data in `high_capacity`
   - Monitor access patterns and adjust as needed

2. **SSD Cache** (if available):
   - Configure SSD cache to prioritize `/volume1/docker/nomad/volumes/high_performance`
   - Use read-only cache for better reliability
   - Monitor cache hit rate to ensure effectiveness

3. **Filesystem Performance**:
   - Btrfs offers better small-file performance than ext4
   - Enable compression for text-heavy data (configs, logs)
   - Consider periodic filesystem maintenance (balance, scrub)

4. **I/O Scheduling**:
   - Avoid running I/O intensive operations simultaneously
   - Schedule backups, garbage collection, and indexing at off-peak times
   - Use `ionice` for background tasks:
     ```bash
     ionice -c 3 backup_command
     ```

### Monitoring I/O Performance

Use Prometheus and Grafana to monitor storage performance:

1. **Key Metrics to Monitor**:
   - Disk IOPS (reads/writes per second)
   - Disk throughput (MB/s)
   - Disk latency (ms)
   - I/O wait time

2. **Example Prometheus Queries**:
   ```
   # Disk I/O utilization
   rate(node_disk_io_time_seconds_total{device="sda"}[5m]) * 100
   
   # Disk read throughput
   rate(node_disk_read_bytes_total{device="sda"}[5m])
   
   # Disk write throughput
   rate(node_disk_written_bytes_total{device="sda"}[5m])
   ```

## Backup Strategies

### Volume-Based Backups

Back up the entire `/volume1/docker/nomad/volumes` directory:

```bash
# Manual backup
tar -czf /volume2/backups/system/volumes-$(date +%Y%m%d).tar.gz -C /volume1/docker/nomad/volumes .

# Or using rsync for incremental backups
rsync -avz --delete /volume1/docker/nomad/volumes/ /volume2/backups/system/volumes/
```

### Service-Specific Backups

Some services require specialized backup procedures:

1. **Consul**:
   ```bash
   # Take a Consul snapshot
   CONSUL_ALLOC=$(nomad job allocs -job consul -latest | tail -n +2 | awk '{print $1}')
   nomad alloc exec -task consul ${CONSUL_ALLOC} consul snapshot save /tmp/consul-snapshot.snap
   nomad alloc exec -task consul ${CONSUL_ALLOC} cat /tmp/consul-snapshot.snap > /volume2/backups/services/consul/consul-snapshot-$(date +%Y%m%d).snap
   ```

2. **Vault**:
   ```bash
   # Check if Vault is unsealed
   VAULT_ALLOC=$(nomad job allocs -job vault -latest | tail -n +2 | awk '{print $1}')
   VAULT_SEALED=$(nomad alloc exec -task vault ${VAULT_ALLOC} vault status -format=json 2>/dev/null | jq -r '.sealed')
   
   if [ "${VAULT_SEALED}" == "false" ]; then
     # Take a Vault snapshot
     nomad alloc exec -task vault ${VAULT_ALLOC} vault operator raft snapshot save /tmp/vault-snapshot.snap
     nomad alloc exec -task vault ${VAULT_ALLOC} cat /tmp/vault-snapshot.snap > /volume2/backups/services/vault/vault-snapshot-$(date +%Y%m%d).snap
   fi
   ```

### Hyper Backup Integration

Configure Synology's Hyper Backup to back up these directories:

1. Install Hyper Backup from Package Center
2. Create a new backup task:
   - Select "Local folder & USB" as destination
   - Connect your external 1TB drive
   - Select `/volume1/docker/nomad/volumes` and `/volume1/docker/nomad/config` as sources
   - Schedule daily backups
   - Configure retention policy
   - Set up pre/post backup scripts (see [Backup and Recovery](backup-recovery.md))

## Monitoring Storage

### Space Utilization

Monitor space usage through DSM and Prometheus:

1. **DSM Storage Manager**:
   - Regular checks via web interface
   - Configure alerts for low space

2. **Prometheus Metrics**:
   ```
   # Volume space usage percentage
   100 - ((node_filesystem_avail_bytes{mountpoint="/volume1"} * 100) / node_filesystem_size_bytes{mountpoint="/volume1"})
   ```

3. **Automated Alerts**:
   ```yaml
   # In Prometheus rules
   - alert: HighDiskUsage
     expr: 100 - ((node_filesystem_avail_bytes * 100) / node_filesystem_size_bytes) > 85
     for: 5m
     labels:
       severity: warning
     annotations:
       summary: "High disk usage (instance {{ $labels.instance }})"
       description: "Disk usage is above 85%\n  VALUE = {{ $value }}\n  LABELS: {{ $labels }}"
   ```

### Inodes Monitoring

Monitor inode usage (especially important for services with many small files):

```
# Inode usage percentage
100 - ((node_filesystem_files_free{mountpoint="/volume1"} * 100) / node_filesystem_files{mountpoint="/volume1"})
```

### Service-Specific Storage Alerts

Configure alerts for specific services that may have high storage growth:

```yaml
# Alert for rapidly growing log storage
- alert: LokiStorageGrowing
  expr: rate(container_fs_usage_bytes{container_name="loki"}[6h]) > 10485760
  for: 15m
  labels:
    severity: warning
  annotations:
    summary: "Loki storage growing rapidly"
    description: "Loki storage is growing at > 10MB/hr\n  VALUE = {{ $value }}\n  LABELS: {{ $labels }}"
```

## Troubleshooting

### Common Storage Issues

1. **Insufficient Disk Space**:
   ```bash
   # Check disk usage
   df -h /volume1
   
   # Find large directories
   du -h --max-depth=1 /volume1/docker/nomad/volumes | sort -hr
   
   # Clean up unnecessary data
   docker system prune -a  # Clean up unused Docker images
   ```

2. **Permission Issues**:
   ```bash
   # Check permissions
   ls -la /volume1/docker/nomad/volumes
   
   # Fix common permission problems
   chmod 755 /volume1/docker/nomad/volumes
   chown -R your-username:users /volume1/docker/nomad/volumes
   ```

3. **Volume Mount Failures**:
   ```bash
   # Check if volume is registered with Nomad
   nomad volume list
   
   # Verify volume in job specification
   nomad job inspect <job-name> | grep -A 10 volume
   
   # Check container mount points
   nomad alloc exec <alloc-id> df -h
   ```

4. **I/O Performance Issues**:
   ```bash
   # Check for I/O-intensive processes
   iostat -x 1
   
   # Monitor disk activity
   iotop
   
   # Check if Synology's RAID is rebuilding or syncing
   cat /proc/mdstat
   ```

### Recovery Procedures

1. **Restoring from Backup**:
   ```bash
   # Stop affected services
   nomad job stop <job-name>
   
   # Restore data
   tar -xzf /volume2/backups/system/volumes-YYYYMMDD.tar.gz -C /volume1/docker/nomad/volumes
   
   # Restart services
   nomad job run /volume1/docker/nomad/jobs/<job-name>.hcl
   ```

2. **Rebuilding a Service Volume**:
   If a service volume is corrupted, you may need to rebuild it:
   ```bash
   # Stop the service
   nomad job stop <service-name>
   
   # Remove corrupted data
   rm -rf /volume1/docker/nomad/volumes/<service>_data/*
   
   # Restore from backup if available
   tar -xzf /volume2/backups/services/<service>_backup.tar.gz -C /volume1/docker/nomad/volumes/<service>_data
   
   # Start the service
   nomad job run /volume1/docker/nomad/jobs/<service-name>.hcl
   ```

3. **Consul Data Recovery**:
   ```bash
   # Stop Consul
   nomad job stop consul
   
   # Restore Consul data
   rm -rf /volume1/docker/nomad/volumes/consul_data/*
   tar -xzf /volume2/backups/services/consul/consul-snapshot-YYYYMMDD.snap -C /volume1/docker/nomad/volumes/consul_data
   
   # Start Consul
   nomad job run /volume1/docker/nomad/jobs/consul.hcl
   ```