# Synology DS923+ Specific Considerations

This document outlines specific considerations, limitations, and best practices for running the HomeLab DevOps Platform on a Synology DS923+ NAS.

## Table of Contents

1. [Hardware Specifications](#hardware-specifications)
2. [DSM Limitations](#dsm-limitations)
3. [Container Manager Considerations](#container-manager-considerations)
4. [Nomad Volume Limitations on Synology](#nomad-volume-limitations-on-synology)
5. [Storage Considerations](#storage-considerations)
6. [Network Configuration](#network-configuration)
7. [Memory Management](#memory-management)
8. [Backup Integration](#backup-integration)
9. [DSM Updates and Maintenance](#dsm-updates-and-maintenance)
10. [Performance Optimization](#performance-optimization)
11. [Security Considerations](#security-considerations)

## Hardware Specifications

The Synology DS923+ has the following specifications that influence our deployment:

- **CPU**: AMD Ryzen R1600 dual-core processor
- **RAM**: 32GB (upgraded from standard 8GB)
- **Storage**: 4x 4TB HDDs in RAID10 configuration (8TB usable)
- **Network**: 1GbE interface (upgradable to 10GbE with add-in card)
- **USB Ports**: USB 3.2 Gen 1 ports for external devices
- **Operating System**: Synology DSM 7.x

The AMD processor may have compatibility implications for some container images that are optimized specifically for Intel processors.

## DSM Limitations

### Container Manager Constraints

Synology's Container Manager package has several limitations:

1. **Storage Location**: Container Manager stores all images and container runtime data at `/var/packages/ContainerManager/var/docker`. This location cannot be changed without breaking Container Manager.

2. **Configuration Modifications**: Attempting to modify `/var/packages/ContainerManager/etc/dockerd.json` can break Container Manager and require repair or reinstallation.

3. **Docker Version**: Container Manager uses a specific Docker version that may not match the latest available. This can cause compatibility issues with newer container features.

4. **Resource Controls**: Container Manager's resource controls may not align perfectly with Nomad's resource specifications.

### System Integration

1. **Synology Services**: Several Synology system services run in the background and consume resources. These cannot be disabled without affecting system functionality.

2. **Package Dependencies**: Some Synology packages create dependencies that must remain intact for system functionality.

3. **File System Access**: DSM restricts access to certain system directories, which can impact container volume mounts.

## Container Manager Considerations

### Image Storage

All Docker images are stored in `/var/packages/ContainerManager/var/docker/overlay2` regardless of where Nomad service data is stored. Consider this when planning your storage allocation.

For a production environment:
- Monitor the space usage of this directory
- Regularly prune unused images with `docker system prune -a`
- Consider setting up periodic cleanup jobs

### Container Lifecycle

The Container Manager may occasionally restart services outside of Nomad's control, particularly after DSM updates. Your Nomad jobs should be designed to handle unexpected restarts gracefully.

### Registry Integration

When using the local Docker Registry:

1. Configure Container Manager to trust your self-signed certificates:
   ```bash
   # Create directory for certificates
   sudo mkdir -p /etc/docker/certs.d/registry.homelab.local:5000

   # Copy your self-signed certificate
   sudo cp /volume1/docker/nomad/config/certs/homelab.crt /etc/docker/certs.d/registry.homelab.local:5000/ca.crt
   ```

2. Restart the Container Manager package after certificate changes.

## Nomad Volume Limitations on Synology

The Synology implementation of Nomad has specific limitations that affect how persistent storage is configured for the HomeLab DevOps Platform.

### Missing Host Volume Support

While standard Nomad installations support the `host` volume type, the Synology version does not support this feature. Attempting to register volumes using `nomad volume create` will result in an "Error unknown volume type" message.

### Alternative Volume Approach

Due to this limitation, the platform uses Docker volume mounts instead of Nomad volumes:

#### Standard Nomad (not supported on Synology):
```hcl
volume "consul_data" {
  type = "host"
  config {
    source = "/volume1/nomad/volumes/consul_data"
  }
}

job "consul" {
  group "consul" {
    volume "consul_data" {
      type = "host"
      read_only = false
      source = "consul_data"
    }
    
    task "consul" {
      volume_mount {
        volume = "consul_data"
        destination = "/consul/data"
        read_only = false
      }
    }
  }
}
```

#### Synology Nomad (supported approach):
```hcl
job "consul" {
  group "consul" {
    task "consul" {
      config {
        image = "consul:latest"
        volumes = [
          "/volume1/nomad/volumes/consul_data:/consul/data"
        ]
      }
    }
  }
}
```

### Installation Script Adaptation

The platform's installation scripts detect the Synology environment and adapt accordingly:

1. The `01-setup-directories.sh` script still creates all necessary directories with appropriate permissions
2. The `02-configure-volumes.sh` script identifies that Nomad doesn't support host volumes and creates a `VOLUME_README.md` file with instructions
3. Job definitions use Docker's volume mount system instead of Nomad's volume system

### Volume Management Implications

This alternative approach has several implications:

1. **Volume Management**: Volumes can't be managed through Nomad commands like `nomad volume list` or `nomad volume status`
2. **Visibility**: There's no central place to view all volumes and their status in Nomad
3. **Allocation Recovery**: If a job is restarted on a different client, the data won't automatically move (but this is less of an issue in a single-node Synology setup)
4. **Permissions**: Container UID/GID mapping requires careful management of host directory permissions

### Best Practices for Synology Volume Management

1. **Directory Structure**: Maintain a consistent directory structure in `/volume1/nomad/volumes/`
2. **Permission Management**: Set appropriate ownership and permissions on host directories to match container users:
   ```bash
   chown -R 472:472 /volume1/nomad/volumes/grafana_data  # Grafana runs as UID 472
   chmod 777 /volume1/nomad/volumes/consul_data  # Consul needs full access
   ```
3. **Documentation**: Keep a reference of volume mappings and required permissions
4. **Backup Strategy**: Back up the entire `/volume1/nomad/volumes/` directory for comprehensive data protection

### Container User IDs on Synology

Common container user IDs that require special permission handling:

| Service | Container UID:GID | Required Permissions |
|---------|------------------|----------------------|
| Grafana | 472:472 | 755 |
| PostgreSQL | 999:999 | 700 |
| Consul | varies (often runs as root) | 777 |
| Prometheus | 65534:65534 (nobody) | 755 |
| Loki | varies | 755 |

Apply these permissions during installation or when troubleshooting permission-related issues.

## Storage Considerations

### RAID Configuration

The DS923+ with 4x 4TB drives in RAID10:
- Provides approximately 8TB of usable storage
- Offers good read/write performance
- Can survive a single drive failure

This configuration provides a good balance of performance and redundancy for a homelab environment.

### Storage Classes

The platform uses logical storage classes to organize data:

1. **high_performance**: For services requiring fast I/O
   - Recommended for: Consul, Vault, Prometheus
   - Located at: `/volume1/docker/nomad/volumes/high_performance`

2. **high_capacity**: For services requiring larger storage
   - Recommended for: Loki, Registry
   - Located at: `/volume1/docker/nomad/volumes/high_capacity`

3. **standard**: For general purpose storage
   - Recommended for: Grafana, Keycloak, Homepage
   - Located at: `/volume1/docker/nomad/volumes/standard`

Though all are located on the same physical RAID array, this organization helps with logical separation and management.

### SSD Cache (Optional)

If you add SSD caching to your DS923+:
1. Configure it as "read-only" cache for best reliability
2. Direct it toward the `/volume1/docker/nomad/volumes/high_performance` directory for maximum benefit

To enable SSD cache in DSM:
- Navigate to Storage Manager > SSD Cache
- Click "Create"
- Select read-only cache unless you have two SSDs for redundancy
- Choose your volume
- Complete the wizard

## Network Configuration

### Static IP Configuration

For stability, configure your DS923+ with a static IP address:

1. In DSM, go to Control Panel > Network > Network Interface
2. Edit your primary network interface
3. Choose "Use manual configuration"
4. Set a static IP within your 10.0.4.0/24 subnet
5. Configure appropriate gateway and DNS servers

### Firewall Configuration

Configure the DSM firewall to allow required services:

1. Go to Control Panel > Security > Firewall
2. Create a profile for your network interface
3. Allow the following ports from your local network (10.0.4.0/24):
   - SSH (22) - From specific management IPs only
   - Nomad (4646-4648)
   - Consul (8300-8302, 8500, 8600)
   - Traefik (80, 443, 8081)

### DNS Configuration

To integrate Consul DNS with Synology's DNS server:

1. Create a custom DNS configuration:
   ```bash
   sudo mkdir -p /etc/dnsmasq.conf.d
   echo "server=/consul/127.0.0.1#8600" | sudo tee /etc/dnsmasq.conf.d/10-consul
   ```

2. Restart the DNS service:
   ```bash
   sudo systemctl restart dnsmasq
   ```

Note that this configuration may be reset after DSM updates.

## Memory Management

### Memory Allocation

With 32GB RAM, allocate memory carefully among services. Recommended allocations:

- **Prometheus**: 4GB (heavy data processing)
- **Loki**: 3GB (log storage and processing)
- **Keycloak**: 2GB (authentication and user management)
- **Vault**: 1.5GB (secrets management)
- **Grafana**: 1GB (visualization)
- **Consul**: 1GB (service discovery)
- **Registry**: 1GB (container storage)
- **Other services**: 0.5GB or less each

Reserve at least 3GB for DSM itself and other Synology services.

### Swap Configuration

Synology manages its own swap space. For optimal performance:

1. Adjust the swappiness parameter for less aggressive swapping:
   ```bash
   echo 10 | sudo tee /proc/sys/vm/swappiness
   ```

2. To make this persistent across reboots, create a scheduled task:
   - Go to Control Panel > Task Scheduler
   - Create a triggered task that runs at boot
   - User: root
   - Command: `echo 10 > /proc/sys/vm/swappiness`

## Backup Integration

### Hyper Backup Integration

Leverage Synology's Hyper Backup for platform data:

1. Install Hyper Backup from Package Center
2. Create a backup task for these directories:
   - `/volume1/docker/nomad/` (configuration)
   - `/volume1/docker/nomad/volumes/` (service data)
3. Configure schedule (daily at off-peak hours)
4. Set retention policy (7 daily, 4 weekly)
5. Configure pre/post-backup scripts:

```bash
# Pre-backup script
#!/bin/bash
# Stop sensitive services
nomad job stop vault
nomad job stop keycloak

# Create Consul snapshot
CONSUL_ALLOC=$(nomad job allocs -job consul -latest | tail -n +2 | awk '{print $1}')
nomad alloc exec -task consul ${CONSUL_ALLOC} consul snapshot save /tmp/consul-snapshot.snap
nomad alloc exec -task consul ${CONSUL_ALLOC} cat /tmp/consul-snapshot.snap > /volume1/docker/nomad/config/consul-snapshot.snap

# Wait for clean shutdown
sleep 10
```

```bash
# Post-backup script
#!/bin/bash
# Restart services
nomad job run /volume1/docker/nomad/jobs/vault.hcl
nomad job run /volume1/docker/nomad/jobs/keycloak.hcl

# Unseal Vault
VAULT_ALLOC=$(nomad job allocs -job vault -latest | tail -n +2 | awk '{print $1}')
nomad alloc exec -task vault ${VAULT_ALLOC} vault operator unseal <key1>
nomad alloc exec -task vault ${VAULT_ALLOC} vault operator unseal <key2>
nomad alloc exec -task vault ${VAULT_ALLOC} vault operator unseal <key3>
```

### External USB Backup

For additional protection:

1. Connect a USB drive to your DS923+
2. Create a backup task in Hyper Backup targeting the USB drive
3. Schedule it less frequently (weekly)
4. Rotate external drives if possible for off-site storage

## DSM Updates and Maintenance

### Before DSM Updates

1. Create a full backup using Hyper Backup
2. Export critical snapshots:
   ```bash
   # Export Consul snapshot
   CONSUL_ALLOC=$(nomad job allocs -job consul -latest | tail -n +2 | awk '{print $1}')
   nomad alloc exec -task consul ${CONSUL_ALLOC} consul snapshot save /volume2/backups/services/consul/consul-snapshot-$(date +%Y%m%d).snap
   
   # Export Vault snapshot (if unsealed)
   VAULT_ALLOC=$(nomad job allocs -job vault -latest | tail -n +2 | awk '{print $1}')
   VAULT_SEALED=$(nomad alloc exec -task vault ${VAULT_ALLOC} vault status -format=json 2>/dev/null | jq -r '.sealed')
   if [ "${VAULT_SEALED}" == "false" ]; then
     nomad alloc exec -task vault ${VAULT_ALLOC} vault operator raft snapshot save /tmp/vault-snapshot.snap
     nomad alloc exec -task vault ${VAULT_ALLOC} cat /tmp/vault-snapshot.snap > /volume2/backups/services/vault/vault-snapshot-$(date +%Y%m%d).snap
   fi
   ```

3. Note down the vault unseal keys

### After DSM Updates

1. Verify Nomad is running:
   ```bash
   systemctl status nomad
   ```

2. If needed, restart Nomad:
   ```bash
   systemctl restart nomad
   ```

3. Check service status:
   ```bash
   nomad job status
   ```

4. Restore DNS configuration if needed:
   ```bash
   sudo mkdir -p /etc/dnsmasq.conf.d
   echo "server=/consul/127.0.0.1#8600" | sudo tee /etc/dnsmasq.conf.d/10-consul
   sudo systemctl restart dnsmasq
   ```

5. Verify network configuration and firewall settings
6. Unseal Vault if needed

## Performance Optimization

### CPU Optimization

The AMD Ryzen R1600 dual-core processor has limited cores. Optimize by:

1. Allocating appropriate CPU shares:
   ```hcl
   resources {
     cpu = 500  # 0.5 cores
   }
   ```

2. Setting CPU priorities:
   - Give higher CPU allocation to critical services (Consul, Vault)
   - Limit CPU for background services

### Disk I/O Optimization

Optimize disk I/O operations:

1. Separate high I/O services (Prometheus, Loki) to different storage paths
2. Schedule intensive operations (like backup and indexing) at different times
3. Consider adding SSD cache for frequently accessed data

### Network Optimization

1. Use jumbo frames if your network supports them:
   - In DSM, go to Control Panel > Network > Network Interface
   - Edit your network interface
   - Enable jumbo frames (MTU 9000) if supported by your network

2. If available, use the 10GbE upgrade for better performance

## Security Considerations

### SSH Configuration

Enhance SSH security:

1. Use key-based authentication:
   ```bash
   # On your client
   ssh-copy-id -i ~/.ssh/id_ed25519.pub your-username@synology-ip
   ```

2. Restrict SSH access by IP:
   ```bash
   # Edit /etc/ssh/sshd_config
   sudo nano /etc/ssh/sshd_config
   
   # Add restriction
   AllowUsers your-username@10.0.4.*
   
   # Restart SSH
   sudo systemctl restart sshd
   ```

### Self-signed Certificate Management

For your self-signed certificates:

1. Create a strong certificate:
   ```bash
   openssl req -x509 -nodes -days 3650 -newkey rsa:4096 \
     -keyout /volume1/docker/nomad/config/certs/homelab.key \
     -out /volume1/docker/nomad/config/certs/homelab.crt \
     -subj "/CN=*.homelab.local" \
     -addext "subjectAltName=DNS:*.homelab.local,DNS:homelab.local"
   ```

2. Distribute to client devices:
   - Windows: Import to "Trusted Root Certification Authorities"
   - macOS: Import to Keychain, set to "Always Trust"
   - Linux: Add to `/usr/local/share/ca-certificates/` and run `update-ca-certificates`
   - iOS/Android: Install profile/certificate via Settings

3. Set a calendar reminder to renew before expiration (3650 days)

### Vault Security

Since Vault contains sensitive credentials:

1. Use strong unseal keys and root token
2. Store unseal keys securely, preferably offline
3. Consider implementing Shamir's Secret Sharing for key distribution
4. Set up audit logging:
   ```hcl
   # In Vault configuration
   audit {
     type = "file"
     path = "/vault/logs/audit.log"
   }
   ```