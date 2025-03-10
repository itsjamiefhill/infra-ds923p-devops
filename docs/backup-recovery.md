# Backup and Recovery Procedures for Synology DS923+

This document outlines the backup and recovery procedures for the HomeLab DevOps Platform on Synology DS923+, ensuring you can protect your data and recover from failures.

## Table of Contents

1. [Backup Strategy Overview](#backup-strategy-overview)
2. [Backup Components](#backup-components)
3. [Synology-Specific Backup Options](#synology-specific-backup-options)
4. [Backup Procedures](#backup-procedures)
5. [Recovery Procedures](#recovery-procedures)
6. [Scheduled Backups](#scheduled-backups)
7. [Verification and Testing](#verification-and-testing)
8. [Special Considerations](#special-considerations)
9. [Disaster Recovery](#disaster-recovery)

## Backup Strategy Overview

The HomeLab DevOps Platform on Synology DS923+ uses a multi-layered backup strategy that leverages both Synology's native tools and custom scripts. The key principles are:

- **Consistent State**: Components are backed up in a consistent state (stopped or using snapshots)
- **Configuration Preservation**: Both data and configuration are backed up
- **Modularity**: Each component can be backed up and restored independently
- **Minimal Downtime**: Services can be backed up with minimal impact to the system
- **Verification**: Backups are tested to ensure they can be restored

## Backup Components

The platform has several components that need to be backed up:

| Component | Data Location | Criticality | Contents |
|-----------|---------------|------------|----------|
| Consul | /volume1/nomad/volumes/consul_data | High | Service registry, KV store |
| Vault | /volume1/nomad/volumes/vault_data | Critical | Secrets, encryption keys, certificates |
| Docker Registry | /volume1/nomad/volumes/registry_data | Medium | Container images |
| Prometheus | /volume1/nomad/volumes/prometheus_data | Low | Historical metrics |
| Grafana | /volume1/nomad/volumes/grafana_data | Medium | Dashboards, users, settings |
| Loki | /volume1/nomad/volumes/loki_data | Low | Log data |
| Keycloak | /volume1/nomad/volumes/keycloak_data | High | User directory, authentication settings |
| Configuration | /volume1/nomad/config | High | Platform configuration |
| Job Definitions | /volume1/nomad/jobs | High | Job definitions |

## Synology-Specific Backup Options

The Synology DS923+ provides several native backup solutions that can be utilized:

### Hyper Backup

Hyper Backup is Synology's comprehensive backup solution that supports:
- Multiple backup destinations (external drives, other Synology devices, cloud)
- Scheduled backups with retention policies
- Data encryption
- Versioning
- Integrity checks
- Efficient incremental backups

To configure Hyper Backup for the platform:

1. Install Hyper Backup from the Package Center
2. Create a new backup task
3. Select destination (external USB drive connected to DS923+)
4. Select these folders:
   - `/volume1/nomad/`
   - `/volume1/nomad/volumes/`
5. Configure schedule (daily at 1:00 AM)
6. Set retention policy (7 daily, 4 weekly)
7. Enable integrity check and compression
8. Configure pre/post-backup scripts (see below)

### Snapshot Replication

For quick point-in-time recovery:
1. Enable Snapshot on your volume
2. Configure snapshot schedule
3. Set retention policy

### USB Copy

For simple external backups:
1. Connect your 1TB external drive
2. Configure USB Copy for automated backups when the drive is connected

## Backup Procedures

### Full Platform Backup Using Hyper Backup

The most comprehensive backup approach uses Synology's Hyper Backup:

1. **Install and Configure Hyper Backup**:
   - Install from Package Center
   - Create backup task for `/volume1/nomad/` to external drive
   - Schedule daily execution

2. **Pre-Backup Script**:
   Create a script at `/volume1/nomad/scripts/pre-backup.sh`:
   ```bash
   #!/bin/bash
   # Pre-backup script to ensure data consistency
   
   # Timestamp for logging
   echo "Starting pre-backup procedures at $(date)" > /volume1/logs/platform/backup.log
   
   # Stop sensitive services
   nomad job stop vault
   nomad job stop keycloak
   
   # Export Consul snapshot
   nomad alloc exec -task consul $(nomad job allocs -job consul -latest | tail -n +2 | awk '{print $1}') consul snapshot save /tmp/consul-snapshot.snap
   nomad alloc exec -task consul $(nomad job allocs -job consul -latest | tail -n +2 | awk '{print $1}') cat /tmp/consul-snapshot.snap > /volume1/nomad/config/consul-snapshot.snap
   
   # Wait for proper shutdown
   sleep 10
   
   echo "Pre-backup procedures completed at $(date)" >> /volume1/logs/platform/backup.log
   ```

3. **Post-Backup Script**:
   Create a script at `/volume1/nomad/scripts/post-backup.sh`:
   ```bash
   #!/bin/bash
   # Post-backup script to restart services
   
   echo "Starting post-backup procedures at $(date)" >> /volume1/logs/platform/backup.log
   
   # Restart services
   nomad job run /volume1/nomad/jobs/vault.hcl
   nomad job run /volume1/nomad/jobs/keycloak.hcl
   
   # Wait for services to start
   sleep 30
   
   # Check service status
   nomad job status vault >> /volume1/logs/platform/backup.log
   nomad job status keycloak >> /volume1/logs/platform/backup.log
   
   echo "Post-backup procedures completed at $(date)" >> /volume1/logs/platform/backup.log
   ```

4. **Configure Hyper Backup Task to Use Scripts**:
   - In Hyper Backup, edit the task
   - Under "Settings", enable "Run script"
   - Set pre-backup script: `/volume1/nomad/scripts/pre-backup.sh`
   - Set post-backup script: `/volume1/nomad/scripts/post-backup.sh`

### Critical Component Manual Backups

For the most critical components, specialized backup procedures may be necessary:

#### Vault Backup

Vault requires special consideration due to its sealed state:

```bash
#!/bin/bash
# Vault backup

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="/volume2/backups/vault/${TIMESTAMP}"
mkdir -p ${BACKUP_DIR}

# Check if Vault is sealed
VAULT_ALLOC=$(nomad job allocs -job vault -latest | tail -n +2 | awk '{print $1}')
VAULT_SEALED=$(nomad alloc exec -task vault ${VAULT_ALLOC} vault status -format=json | jq -r '.sealed')

if [ "${VAULT_SEALED}" == "false" ]; then
  # If unsealed, take a snapshot
  echo "Taking Vault snapshot..."
  nomad alloc exec -task vault ${VAULT_ALLOC} vault operator raft snapshot save /tmp/vault-snapshot.snap
  nomad alloc exec -task vault ${VAULT_ALLOC} cat /tmp/vault-snapshot.snap > ${BACKUP_DIR}/vault-snapshot.snap
fi

# Stop Vault for consistent file backup
nomad job stop vault

# File-based backup
tar -czf ${BACKUP_DIR}/vault_data.tar.gz -C /volume1/nomad/volumes vault_data

# Restart Vault
nomad job run /volume1/nomad/jobs/vault.hcl

echo "Vault backup completed. YOU WILL NEED TO UNSEAL VAULT NOW."
echo "Backup stored at ${BACKUP_DIR}"
```

#### Consul Backup

Consul can be backed up while running using its snapshot feature:

```bash
#!/bin/bash
# Consul backup

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="/volume2/backups/consul/${TIMESTAMP}"
mkdir -p ${BACKUP_DIR}

# Take a Consul snapshot
CONSUL_ALLOC=$(nomad job allocs -job consul -latest | tail -n +2 | awk '{print $1}')
echo "Taking Consul snapshot..."
nomad alloc exec -task consul ${CONSUL_ALLOC} consul snapshot save /tmp/consul-snapshot.snap
nomad alloc exec -task consul ${CONSUL_ALLOC} cat /tmp/consul-snapshot.snap > ${BACKUP_DIR}/consul-snapshot.snap

echo "Consul backup completed at ${BACKUP_DIR}"
```

## Recovery Procedures

### Full Platform Recovery

To restore the entire platform from a Hyper Backup:

1. **Install DSM and Required Packages**:
   - Complete Stage 0 setup as documented
   - Install Hyper Backup

2. **Restore from Hyper Backup**:
   - Connect the external backup drive
   - Open Hyper Backup, go to Restore
   - Select the backup task and version to restore
   - Select restoration of `/volume1/nomad/` directory
   - Start the restoration process

3. **Post-Restore Steps**:
   ```bash
   # Fix permissions
   chown -R your-username:users /volume1/nomad
   chown -R 472:472 /volume1/nomad/volumes/grafana_data
   
   # Start core services in order
   nomad job run /volume1/nomad/jobs/consul.hcl
   sleep 10
   nomad job run /volume1/nomad/jobs/traefik.hcl
   sleep 5
   nomad job run /volume1/nomad/jobs/vault.hcl
   
   # Unseal Vault
   # Get the Vault allocation ID
   VAULT_ALLOC=$(nomad job allocs -job vault -latest | tail -n +2 | awk '{print $1}')
   
   # Unseal Vault (repeat with each key)
   nomad alloc exec -task vault ${VAULT_ALLOC} vault operator unseal <key1>
   nomad alloc exec -task vault ${VAULT_ALLOC} vault operator unseal <key2>
   nomad alloc exec -task vault ${VAULT_ALLOC} vault operator unseal <key3>
   
   # Start remaining services
   nomad job run /volume1/nomad/jobs/registry.hcl
   nomad job run /volume1/nomad/jobs/prometheus.hcl
   nomad job run /volume1/nomad/jobs/grafana.hcl
   nomad job run /volume1/nomad/jobs/loki.hcl
   nomad job run /volume1/nomad/jobs/promtail.hcl
   nomad job run /volume1/nomad/jobs/keycloak.hcl
   nomad job run /volume1/nomad/jobs/oidc-proxy.hcl
   nomad job run /volume1/nomad/jobs/homepage.hcl
   ```

### Critical Component Recovery

For the most critical components, specialized recovery procedures may be necessary:

#### Vault Recovery

Restoring Vault requires extra care due to unsealing requirements:

```bash
#!/bin/bash
# Vault recovery

BACKUP_DIR="/volume2/backups/vault/<timestamp>"

# Stop Vault
nomad job stop vault

# Restore from file backup
rm -rf /volume1/nomad/volumes/vault_data
tar -xzf ${BACKUP_DIR}/vault_data.tar.gz -C /volume1/nomad/volumes

# Restart Vault
nomad job run /volume1/nomad/jobs/vault.hcl

# Get the Vault allocation ID
VAULT_ALLOC=$(nomad job allocs -job vault -latest | tail -n +2 | awk '{print $1}')

# Unseal Vault
nomad alloc exec -task vault ${VAULT_ALLOC} vault operator unseal <key1>
nomad alloc exec -task vault ${VAULT_ALLOC} vault operator unseal <key2>
nomad alloc exec -task vault ${VAULT_ALLOC} vault operator unseal <key3>

echo "Vault data restored and unsealed."
```

#### Consul Recovery

Restoring Consul from a snapshot:

```bash
#!/bin/bash
# Consul recovery from snapshot

BACKUP_FILE="/volume2/backups/consul/<timestamp>/consul-snapshot.snap"

# Get the Consul allocation ID
CONSUL_ALLOC=$(nomad job allocs -job consul -latest | tail -n +2 | awk '{print $1}')

# Copy snapshot to container
nomad alloc exec -task consul ${CONSUL_ALLOC} cp ${BACKUP_FILE} /tmp/restore.snap

# Restore from snapshot
nomad alloc exec -task consul ${CONSUL_ALLOC} consul snapshot restore /tmp/restore.snap

echo "Consul snapshot restored."
```

## Scheduled Backups

To automate backups, configure Hyper Backup task schedule:

1. In Hyper Backup, edit your backup task
2. Go to "Settings" tab
3. Under "Backup schedule", set your preferred interval:
   - Daily backup at 2 AM
   - Enable "Run backup immediately after scheduled time is reached"
4. Configure data retention:
   - Keep 7 daily backups
   - Keep 4 weekly backups
   - Keep 3 monthly backups

For additional protection, create a Nomad batch job for critical components:

```hcl
job "backup-critical" {
  datacenters = ["dc1"]
  type = "batch"
  
  periodic {
    cron = "0 1 * * *"  # Daily at 1 AM
    prohibit_overlap = true
  }

  group "backup" {
    task "backup-script" {
      driver = "exec"
      
      config {
        command = "/bin/bash"
        args    = ["/volume1/nomad/scripts/critical-backup.sh"]
      }
      
      resources {
        cpu    = 200
        memory = 128
      }
    }
  }
}
```

## Verification and Testing

Regularly test your backups to ensure they can be restored:

```bash
#!/bin/bash
# Backup verification script

# Set variables
LATEST_BACKUP=$(find /volume2/backups -type d -name "2*" | sort -r | head -n 1)
TEST_RESTORE_DIR="/tmp/backup-test"

# Test Consul snapshot
if [ -f "${LATEST_BACKUP}/consul-snapshot.snap" ]; then
  echo "Testing Consul snapshot..."
  
  # Get the Consul allocation ID
  CONSUL_ALLOC=$(nomad job allocs -job consul -latest | tail -n +2 | awk '{print $1}')
  
  # Copy snapshot to container
  nomad alloc exec -task consul ${CONSUL_ALLOC} cp ${LATEST_BACKUP}/consul-snapshot.snap /tmp/test.snap
  
  # Use Consul API to validate snapshot without restoring
  SNAPSHOT_INFO=$(nomad alloc exec -task consul ${CONSUL_ALLOC} consul snapshot inspect /tmp/test.snap)
  
  if [[ $? -eq 0 ]]; then
    echo "✓ Consul snapshot verification successful"
  else
    echo "✗ Consul snapshot verification failed"
  fi
fi

# Verify archive integrity for key components
for component in keycloak_data vault_data registry_data grafana_data homepage_data; do
  if [ -f "${LATEST_BACKUP}/${component}.tar.gz" ]; then
    echo "Testing ${component} archive..."
    
    # Test archive integrity
    tar -tzf ${LATEST_BACKUP}/${component}.tar.gz > /dev/null 2>&1
    if [ $? -eq 0 ]; then
      echo "✓ ${component} archive verification successful"
    else
      echo "✗ ${component} archive verification failed"
    fi
  fi
done
```

## Special Considerations

### Vault Unsealing

After a Vault restore, you'll need to unseal it:

```bash
# Get Vault allocation ID
VAULT_ALLOC=$(nomad job allocs -job vault -latest | tail -n +2 | awk '{print $1}')

# Unseal Vault using your unseal keys
nomad alloc exec -task vault $VAULT_ALLOC vault operator unseal <key1>
nomad alloc exec -task vault $VAULT_ALLOC vault operator unseal <key2>
nomad alloc exec -task vault $VAULT_ALLOC vault operator unseal <key3>
```

### Synology DSM Update Considerations

Before DSM updates:
1. Create a full backup using Hyper Backup
2. Export critical snapshots (Consul, Vault)
3. Note down the vault unseal keys

After DSM updates:
1. Verify all volumes and data directories are accessible
2. Check that Nomad service is running
3. Restart any services that didn't auto-restart
4. Unseal Vault if needed

### OIDC Configuration

When restoring OIDC components:

1. Ensure Keycloak is fully restored before restoring the OIDC proxy
2. Verify client secrets and authentication flows after restoration
3. Test authentication with a few services to ensure integration is working

## Disaster Recovery

### Complete System Failure

In case of complete Synology system failure:

1. **Get a replacement Synology unit**
2. **Install DSM and configure it** following Stage 0 documentation
3. **Install Hyper Backup** from Package Center
4. **Restore from your backup device**:
   - Connect your external backup drive
   - Use Hyper Backup Restore to recover data
5. **Follow the post-restore steps** documented above
6. **Unseal Vault**
7. **Verify all services** have started correctly
8. **Test the authentication flow**

### Migration to New Hardware

To migrate to new Synology hardware:

1. Create a full backup on the old system using Hyper Backup
2. Set up the new system with DSM
3. Install prerequisites (Nomad, Container Manager)
4. Restore using Hyper Backup Restore
5. Follow the same post-restore procedures

### Backup Encryption

For sensitive environments, encrypt your Hyper Backup:

1. When configuring your Hyper Backup task, enable "Back up with encryption"
2. Set a strong encryption password
3. Store this password securely, as it will be required for any restoration

## Conclusion

This backup and recovery strategy leverages Synology's native tools while adding specialized procedures for the HomeLab DevOps Platform components. By following these procedures, you can ensure your platform data is protected and can be recovered in case of failure.

Regular testing of both backups and recovery procedures is essential to maintain confidence in your disaster recovery capability.