# 6. troubleshooting/synology.md
# Synology-Specific Troubleshooting

This document covers Synology-specific issues that may arise with the HomeLab DevOps Platform on a Synology DS923+ NAS.

## Table of Contents

1. [DSM Updates and Maintenance](#dsm-updates-and-maintenance)
2. [Container Manager Problems](#container-manager-problems)
3. [Resource Management](#resource-management)
4. [Directory Permissions](#directory-permissions)
5. [Synology Limitations and Workarounds](#synology-limitations-and-workarounds)

## DSM Updates and Maintenance

### After DSM Updates

If you encounter issues after DSM updates:

1. Check if Nomad is still running:
   ```bash
   systemctl status nomad
   ```

2. Restart Nomad if needed:
   ```bash
   systemctl restart nomad
   ```

3. Restore Consul DNS configuration:
   ```bash
   sudo cp /volume1/docker/nomad/config/10-consul /etc/dnsmasq.conf.d/
   sudo systemctl restart dnsmasq
   ```

4. Check service status:
   ```bash
   nomad job status
   ```

5. Re-export Nomad SSL environment variables:
   ```bash
   export NOMAD_ADDR=https://127.0.0.1:4646
   export NOMAD_CACERT=/var/packages/nomad/shares/nomad/etc/certs/nomad-ca.pem
   export NOMAD_CLIENT_CERT=/var/packages/nomad/shares/nomad/etc/certs/nomad-cert.pem
   export NOMAD_CLIENT_KEY=/var/packages/nomad/shares/nomad/etc/certs/nomad-key.pem
   ```

### Backup Script for DSM Update

Create a pre-update backup script:

```bash
#!/bin/bash
# pre-update-backup.sh

# Create backup directory
BACKUP_DIR="/volume2/backups/pre-update-$(date +%Y%m%d)"
mkdir -p $BACKUP_DIR

# Backup Nomad configuration
cp -r /var/packages/nomad/var/chroot/etc/nomad-config.d $BACKUP_DIR/

# Backup certificates
cp -r /var/packages/nomad/shares/nomad/etc/certs $BACKUP_DIR/

# Backup DNS configuration
cp -r /etc/hosts $BACKUP_DIR/
cp -r /etc/dnsmasq.conf.d $BACKUP_DIR/

# Backup Nomad token
if [ -f "/volume1/docker/nomad/config/nomad_auth.conf" ]; then
  cp /volume1/docker/nomad/config/nomad_auth.conf $BACKUP_DIR/
fi

# Create service snapshots
# Consul
CONSUL_ALLOC=$(nomad job allocs -job consul -latest 2>/dev/null | tail -n +2 | awk '{print $1}')
if [ -n "$CONSUL_ALLOC" ]; then
  nomad alloc exec -task consul ${CONSUL_ALLOC} consul snapshot save /tmp/consul-snapshot.snap
  nomad alloc exec -task consul ${CONSUL_ALLOC} cat /tmp/consul-snapshot.snap > $BACKUP_DIR/consul-snapshot.snap
fi

# Vault (if unsealed)
VAULT_ALLOC=$(nomad job allocs -job vault -latest 2>/dev/null | tail -n +2 | awk '{print $1}')
if [ -n "$VAULT_ALLOC" ]; then
  VAULT_SEALED=$(nomad alloc exec -task vault ${VAULT_ALLOC} vault status -format=json 2>/dev/null | jq -r '.sealed')
  if [ "$VAULT_SEALED" == "false" ]; then
    nomad alloc exec -task vault ${VAULT_ALLOC} vault operator raft snapshot save /tmp/vault-snapshot.snap
    nomad alloc exec -task vault ${VAULT_ALLOC} cat /tmp/vault-snapshot.snap > $BACKUP_DIR/vault-snapshot.snap
  fi
fi

echo "Backup completed to $BACKUP_DIR"
```

### Post-Update Restoration

Create a post-update restoration script:

```bash
#!/bin/bash
# post-update-restore.sh

# Find the latest backup
BACKUP_DIR=$(find /volume2/backups -name "pre-update-*" -type d | sort -r | head -n 1)

if [ -z "$BACKUP_DIR" ]; then
  echo "No backup directory found!"
  exit 1
fi

echo "Restoring from $BACKUP_DIR"

# Restore DNS configuration
if [ -d "$BACKUP_DIR/dnsmasq.conf.d" ]; then
  sudo cp -r $BACKUP_DIR/dnsmasq.conf.d/* /etc/dnsmasq.conf.d/
  sudo systemctl restart dnsmasq
fi

# Restore hosts file entries
if [ -f "$BACKUP_DIR/hosts" ]; then
  # Extract homelab and consul entries
  grep -E "homelab|consul" $BACKUP_DIR/hosts > /tmp/hosts_entries
  
  # Add them to current hosts file
  while read -r line; do
    if ! grep -q "$line" /etc/hosts; then
      echo "$line" | sudo tee -a /etc/hosts
    fi
  done < /tmp/hosts_entries
  
  rm /tmp/hosts_entries
fi

# Restore Nomad token
if [ -f "$BACKUP_DIR/nomad_auth.conf" ]; then
  cp $BACKUP_DIR/nomad_auth.conf /volume1/docker/nomad/config/
  chmod 600 /volume1/docker/nomad/config/nomad_auth.conf
fi

echo "Restoration completed"
```

## Container Manager Problems

### Container Manager Not Starting

If Synology's Container Manager isn't working:

1. Restart the package:
   ```bash
   synopkg restart ContainerManager
   ```

2. Check logs:
   ```bash
   sudo cat /var/log/messages | grep docker
   ```

3. Verify Docker daemon is running:
   ```bash
   ps aux | grep dockerd
   ```

4. Check storage space for Docker:
   ```bash
   df -h /var/packages/ContainerManager/var/docker
   ```

### Docker Storage Space Issues

If Docker is running out of space:

1. Check current usage:
   ```bash
   sudo du -sh /var/packages/ContainerManager/var/docker/overlay2
   ```

2. Clean up unused images:
   ```bash
   sudo docker system prune -a
   ```

3. Remove old containers:
   ```bash
   sudo docker container prune
   ```

4. Remove volumes not used by at least one container:
   ```bash
   sudo docker volume prune
   ```

### Container Manager and Certificate Trust

To make Container Manager trust your self-signed certificates:

1. Create certificate directory:
   ```bash
   sudo mkdir -p /etc/docker/certs.d/registry.homelab.local:5000
   ```

2. Copy your certificate:
   ```bash
   sudo cp /volume1/docker/nomad/config/certs/homelab.crt /etc/docker/certs.d/registry.homelab.local:5000/ca.crt
   ```

3. Restart Container Manager:
   ```bash
   synopkg restart ContainerManager
   ```

## Resource Management

### Memory Management

If you're experiencing memory pressure:

1. Check memory usage:
   ```bash
   free -h
   ```

2. Adjust swappiness for less aggressive swapping:
   ```bash
   echo 10 | sudo tee /proc/sys/vm/swappiness
   ```

3. Make it persistent across reboots:
   - Go to Control Panel > Task Scheduler
   - Create a triggered task that runs at boot
   - User: root
   - Command: `echo 10 > /proc/sys/vm/swappiness`

4. Review memory allocation for services:
   ```bash
   # Edit config/custom.conf
   PROMETHEUS_MEMORY=2048   # Lower from 4096
   LOKI_MEMORY=2048         # Lower from 3072
   ```

### CPU Optimization

For better CPU performance:

1. Allocate appropriate CPU shares:
   ```hcl
   resources {
     cpu = 500  # 0.5 cores
   }
   ```

2. Check CPU usage by service:
   ```bash
   sudo docker stats
   ```

3. Set CPU priorities:
   - Give higher CPU allocation to critical services (Consul, Vault)
   - Limit CPU for background services

4. Consider direct Docker deployment for critical services:
   ```bash
   sudo docker run -d --name consul \
     --restart always \
     --network host \
     --cpus 0.5 \
     -v ${DATA_DIR}/consul_data:/consul/data \
     hashicorp/consul:1.15.4 \
     agent -server -bootstrap -ui
   ```

### Disk I/O Management

For disk I/O optimization:

1. Move high I/O services to different physical volumes if available:
   ```bash
   # Edit config/custom.conf
   PROMETHEUS_DATA_DIR=/volume2/docker/nomad/volumes/prometheus_data
   ```

2. Schedule intensive operations (like backup and indexing) at different times.

3. Consider enabling SSD cache for frequently accessed data.

## Directory Permissions

### Directory Permission Issues After Updates

After DSM updates, permissions might revert:

1. Identify directories with permission issues:
   ```bash
   ls -la /volume1/docker/nomad/volumes/
   ```

2. Fix specific service directories:
   ```bash
   sudo chown -R 472:472 /volume1/docker/nomad/volumes/grafana_data
   sudo chmod 777 /volume1/docker/nomad/volumes/consul_data
   ```

3. Create a permission fix script:
   ```bash
   #!/bin/bash
   # fix-permissions.sh
   
   # Fix common directories
   sudo chown -R 472:472 /volume1/docker/nomad/volumes/grafana_data
   sudo chmod 777 /volume1/docker/nomad/volumes/consul_data
   sudo chown -R 999:999 /volume1/docker/nomad/volumes/postgres_data
   
   echo "Permissions restored"
   ```

4. Schedule this to run after DSM updates:
   - Go to Control Panel > Task Scheduler
   - Create a scheduled task
   - Set to run once after midnight
   - Command: `/volume1/docker/nomad/bin/fix-permissions.sh`

### Managing Service UIDs/GIDs

Maintain a reference for common UIDs/GIDs:

| Service | Container UID:GID | Required Permissions |
|---------|------------------|----------------------|
| Grafana | 472:472 | 755 |
| PostgreSQL | 999:999 | 700 |
| Consul | 100:1000 | 777 |
| Prometheus | 65534:65534 | 755 |
| Loki | varies | 755 |

## Synology Limitations and Workarounds

### Nomad Volume Limitations

Traditional Nomad host volumes aren't supported. Use mount directives instead:

```hcl
mount {
  type = "bind"
  source = "/volume1/docker/nomad/volumes/service_data"
  target = "/container/path"
  readonly = false
}
```

### Container Management Options

For core services with networking needs, direct Docker is often more reliable:

```bash
# Start Consul with Docker
sudo docker run -d --name consul \
  --restart always \
  --network host \
  -v ${DATA_DIR}/consul_data:/consul/data \
  hashicorp/consul:1.15.4 \
  agent -server -bootstrap \
  -bind=$(hostname -I | awk '{print $1}') \
  -advertise=$(hostname -I | awk '{print $1}') \
  -client=0.0.0.0 \
  -ui
```

For application services, Nomad works well:

```bash
# Deploy with Nomad
nomad job run /volume1/docker/nomad/jobs/grafana.hcl
```

### DNS Integration on Synology

Synology has limited dnsmasq support. Use hosts file for best compatibility:

```bash
# Add entries directly
echo "127.0.0.1 consul.service.consul" | sudo tee -a /etc/hosts

# For wildcard domains, add specific entries
echo "10.0.4.78 traefik.homelab.local" | sudo tee -a /etc/hosts
```

### Package Manager Limitations

Synology lacks a full package manager. Install additional tools manually:

```bash
# For common tools, use ipkg
wget -O - http://ipkg.nslu2-linux.org/optware-bootstrap/optware-bootstrap.sh | sh

# Then install packages
ipkg update
ipkg install bind-tools  # For dig
```

### DSM Service Management

DSM's service manager is different from standard systemd:

```bash
# To restart Nomad
sudo synoservice --restart nomad

# Check status 
sudo synoservice --status nomad

# For services not managed by synoservice
sudo systemctl restart docker
```

### Resource Limits in DSM

DSM imposes some resource limits that may affect container performance:

1. Check DSM resource limits:
   - Go to Control Panel > Task Manager
   - Check if any services are being throttled

2. Adjust Nomad job resource specifications:
   ```hcl
   resources {
     cpu    = 500  # 0.5 cores
     memory = 512  # 512 MB
   }
   ```

3. In Container Manager, set resource limits:
   - Open Container Manager
   - Edit container settings
   - Set CPU and memory limits

### DSM Firewall Integration

Synology's firewall might block services. Configure it properly:

1. Go to Control Panel > Security > Firewall
2. Create or edit a profile for your network interface
3. Allow these ports from your local network:
   - SSH (22) - From specific management IPs only
   - Nomad (4646-4648)
   - Consul (8300-8302, 8500, 8600)
   - Traefik (80, 443, 8081)

### Dealing with Synology Network Interfaces

If your Synology has multiple network interfaces:

1. Identify your primary interface:
   ```bash
   ip route get 1 | awk '{print $7;exit}' 2>/dev/null || hostname -I | awk '{print $1}'
   ```

2. For Docker containers, specify bindings:
   ```bash
   PRIMARY_IP=$(ip route get 1 | awk '{print $7;exit}' 2>/dev/null || hostname -I | awk '{print $1}')
   
   docker run -d --name service \
     -p ${PRIMARY_IP}:8080:8080 \
     service-image:latest
   ```

3. For Nomad jobs, specify in the configuration:
   ```hcl
   network {
     port "http" {
       static = 8080
       host_network = "default"  # The default interface
     }
   }
   ```

## Synology and Nomad SSL

### Nomad SSL Environment Setup

To properly configure Nomad SSL on Synology:

1. Set up environment variables:
   ```bash
   export NOMAD_ADDR=https://127.0.0.1:4646
   export NOMAD_CACERT=/var/packages/nomad/shares/nomad/etc/certs/nomad-ca.pem
   export NOMAD_CLIENT_CERT=/var/packages/nomad/shares/nomad/etc/certs/nomad-cert.pem
   export NOMAD_CLIENT_KEY=/var/packages/nomad/shares/nomad/etc/certs/nomad-key.pem
   ```

2. Make it permanent for your user:
   ```bash
   echo 'export NOMAD_ADDR=https://127.0.0.1:4646' >> ~/.bashrc
   echo 'export NOMAD_CACERT=/var/packages/nomad/shares/nomad/etc/certs/nomad-ca.pem' >> ~/.bashrc
   echo 'export NOMAD_CLIENT_CERT=/var/packages/nomad/shares/nomad/etc/certs/nomad-cert.pem' >> ~/.bashrc
   echo 'export NOMAD_CLIENT_KEY=/var/packages/nomad/shares/nomad/etc/certs/nomad-key.pem' >> ~/.bashrc
   ```

3. Create a script for quick sourcing:
   ```bash
   echo '#!/bin/bash
   export NOMAD_ADDR=https://127.0.0.1:4646
   export NOMAD_CACERT=/var/packages/nomad/shares/nomad/etc/certs/nomad-ca.pem
   export NOMAD_CLIENT_CERT=/var/packages/nomad/shares/nomad/etc/certs/nomad-cert.pem
   export NOMAD_CLIENT_KEY=/var/packages/nomad/shares/nomad/etc/certs/nomad-key.pem
   
   # Load token if available
   if [ -f "/volume1/docker/nomad/config/nomad_auth.conf" ]; then
     source "/volume1/docker/nomad/config/nomad_auth.conf"
     export NOMAD_TOKEN
   fi' > /volume1/docker/nomad/bin/nomad-ssl-env.sh
   
   chmod +x /volume1/docker/nomad/bin/nomad-ssl-env.sh
   ```

4. Include the script in your deployment scripts:
   ```bash
   #!/bin/bash
   # Example deployment script
   
   # Source Nomad SSL environment
   source /volume1/docker/nomad/bin/nomad-ssl-env.sh
   
   # Now run Nomad commands
   nomad job run /volume1/docker/nomad/jobs/service.hcl
   ```

### Troubleshooting Nomad SSL on Synology

If you encounter SSL-related issues:

1. Verify certificate paths:
   ```bash
   ls -la /var/packages/nomad/shares/nomad/etc/certs/
   ```

2. Check permissions:
   ```bash
   # Ensure you can read the certificates
   sudo chmod 644 /var/packages/nomad/shares/nomad/etc/certs/nomad-ca.pem
   sudo chmod 644 /var/packages/nomad/shares/nomad/etc/certs/nomad-cert.pem
   sudo chmod 600 /var/packages/nomad/shares/nomad/etc/certs/nomad-key.pem
   ```

3. Test direct connection (for debugging only):
   ```bash
   curl -k https://127.0.0.1:4646/v1/agent/members
   ```

4. Try with proper certificates:
   ```bash
   curl --cacert $NOMAD_CACERT --cert $NOMAD_CLIENT_CERT --key $NOMAD_CLIENT_KEY https://127.0.0.1:4646/v1/agent/members
   ```

## Performance Tuning on Synology

### SSD Cache

If you have SSDs available:

1. Navigate to Storage Manager > SSD Cache
2. Configure "read-only" cache for best reliability
3. Target the `/volume1/docker/nomad/volumes/high_performance` directory

### Memory Tuning

For optimal memory performance:

1. Adjust swappiness for less aggressive swapping:
   ```bash
   echo 10 | sudo tee /proc/sys/vm/swappiness
   ```

2. Create a more efficient memory allocation pattern:
   ```bash
   # High priority services - more memory
   VAULT_MEMORY=1536     # 1.5GB for Vault
   CONSUL_MEMORY=1024    # 1GB for Consul
   
   # Medium priority services
   PROMETHEUS_MEMORY=3072    # 3GB for Prometheus
   GRAFANA_MEMORY=512        # 512MB for Grafana
   
   # Lower priority services
   HOMEPAGE_MEMORY=256       # 256MB for Homepage
   ```

### CPU Priority Tuning

For better CPU performance:

1. Set CPU priorities in Nomad:
   ```hcl
   resources {
     cpu = 1000  # Higher priority (1 core)
   }
   ```

2. For Docker containers, set CPU limits:
   ```bash
   docker run --cpus 0.5 --name service service-image:latest
   ```

3. Consider running resource-intensive operations during low-usage periods.

## Recovery Procedures for Synology

### System Recovery

If your Synology system becomes unstable:

1. Back up essential configuration:
   ```bash
   cp -r /volume1/docker/nomad/config /volume2/backups/config-$(date +%Y%m%d)
   cp -r /volume1/docker/nomad/jobs /volume2/backups/jobs-$(date +%Y%m%d)
   ```

2. Restart the Synology:
   - Use DSM > Control Panel > Hardware & Power > Power
   - Select "Restart"

3. After restart, check services:
   ```bash
   systemctl status nomad
   sudo docker ps
   ```

4. Restart core services if needed:
   ```bash
   # Source SSL environment
   source /volume1/docker/nomad/bin/nomad-ssl-env.sh
   
   # Start Consul (direct Docker)
   /volume1/docker/nomad/bin/start-consul.sh
   
   # Start other services
   nomad job run /volume1/docker/nomad/jobs/traefik.hcl
   ```

### Data Recovery

If you need to recover data:

1. Restore from backup:
   ```bash
   # Find the latest backup
   LATEST_BACKUP=$(find /volume2/backups -name "consul-snapshot-*" -type f | sort -r | head -n 1)
   
   # Restore Consul data
   cp $LATEST_BACKUP /volume1/docker/nomad/volumes/consul_data/
   ```

2. For Vault, restore and unseal:
   ```bash
   # Restore Vault data
   cp /volume2/backups/vault-snapshot-latest.snap /volume1/docker/nomad/volumes/vault_data/
   
   # Restart Vault
   nomad job run /volume1/docker/nomad/jobs/vault.hcl
   
   # Unseal Vault
   VAULT_ALLOC=$(nomad job allocs -job vault -latest | tail -n +2 | awk '{print $1}')
   nomad alloc exec -task vault ${VAULT_ALLOC} vault operator unseal <key1>
   nomad alloc exec -task vault ${VAULT_ALLOC} vault operator unseal <key2>
   nomad alloc exec -task vault ${VAULT_ALLOC} vault operator unseal <key3>
   ```

### Dealing with Synology Package Manager Issues

If Package Manager is having issues:

1. Restart the Package Center service:
   ```bash
   sudo synoservice --restart pkgctl-PackageStation
   ```

2. Check package status:
   ```bash
   synopkg list
   ```

3. Reinstall problematic packages:
   ```bash
   synopkg uninstall ContainerManager
   # Then reinstall from Package Center
   ```

## Virtualization and Container Limits

Synology has some container limitations to be aware of:

1. Resource limits may be enforced by DSM
2. Nested virtualization is generally not supported
3. Some kernel features might be limited
4. Docker host networking might have restrictions

For best results:
- Keep containers simple
- Don't use nested containers
- Use host networking for critical services
- Monitor resource usage