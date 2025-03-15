# 4. troubleshooting/volumes.md
# Volume and Data Troubleshooting

This document covers troubleshooting for volume configuration, mount directives, and data persistence issues in the HomeLab DevOps Platform.

## Table of Contents

1. [Volume Configuration Approaches](#volume-configuration-approaches)
2. [Mount Directive Issues](#mount-directive-issues)
3. [Volume Permission Issues](#volume-permission-issues)
4. [Data Persistence Issues](#data-persistence-issues)
5. [Container Manager Volume Issues](#container-manager-volume-issues)
6. [Synology-Specific Volume Considerations](#synology-specific-volume-considerations)

## Volume Configuration Approaches

The platform supports two main approaches for configuring volumes:

1. **Mount Directive** (Recommended):
   ```hcl
   mount {
     type = "bind"
     source = "/volume1/docker/nomad/volumes/service_data"
     target = "/container/path"
     readonly = false
   }
   ```

2. **Volumes Array** (Alternative):
   ```hcl
   volumes = [
     "/volume1/docker/nomad/volumes/service_data:/container/path"
   ]
   ```

If you're having issues with one approach, try the other to see if it resolves the problem.

### Troubleshooting Steps for Volume Configuration

1. Check that directories exist on the host:
   ```bash
   ls -la /volume1/docker/nomad/volumes/
   ```

2. Verify job configuration has the correct paths:
   ```bash
   nomad job inspect <job-name> | grep -A 10 volume
   ```

3. Validate job definition syntax:
   ```bash
   nomad job validate <job-file>.hcl
   ```

## Mount Directive Issues

### Mount Directive Not Working

**Issue**:
When using the `mount` directive, the container can't access the volume or the job fails to start.

**Cause**:
- Directory doesn't exist on the host
- Permission issues
- Syntax error in the mount configuration
- Docker driver limitation on Synology

**Solution**:

1. Verify the directory exists and has correct permissions:
   ```bash
   ls -la /volume1/docker/nomad/volumes/service_data
   sudo mkdir -p /volume1/docker/nomad/volumes/service_data
   sudo chmod 755 /volume1/docker/nomad/volumes/service_data
   ```

2. Check your job definition for the correct mount syntax:
   ```hcl
   mount {
     type = "bind"
     source = "/volume1/docker/nomad/volumes/service_data"
     target = "/container/path"
     readonly = false
   }
   ```

3. Try the alternative volumes approach instead:
   ```hcl
   volumes = [
     "/volume1/docker/nomad/volumes/service_data:/container/path"
   ]
   ```

4. Validate the job definition before running:
   ```bash
   nomad job validate job-file.hcl
   ```

### Multiple Mount Points

If you're trying to mount multiple directories:

```hcl
config {
  image = "service-image:latest"
  
  mount {
    type = "bind"
    source = "/volume1/docker/nomad/volumes/data1"
    target = "/container/path1"
    readonly = false
  }
  
  mount {
    type = "bind"
    source = "/volume1/docker/nomad/volumes/data2"
    target = "/container/path2"
    readonly = true
  }
}
```

Make sure each directory exists and has appropriate permissions.

## Volume Permission Issues

### Volume Permissions Issues

**Issue**:
Container cannot write to the mounted volume or you see permission errors in logs.

**Cause**:
The container's user ID (UID) doesn't have write permissions to the mounted directory on the host.

**Solution**:
Set the correct ownership on the host directory to match the container's user:

1. Find the UID and GID that the service uses inside the container:

   Common UIDs for services:
   - Grafana: 472:472
   - PostgreSQL: 999:999
   - Prometheus: 65534:65534 (nobody user)
   - Consul: 100:1000 (varies)

2. Apply the correct ownership:
   ```bash
   sudo chown -R <UID>:<GID> /volume1/docker/nomad/volumes/service_data
   ```

3. Set adequate permissions:
   ```bash
   sudo chmod -R 755 /volume1/docker/nomad/volumes/service_data
   ```

4. For services needing write access by multiple users, use more permissive settings:
   ```bash
   sudo chmod 777 /volume1/docker/nomad/volumes/consul_data
   ```

### "Permission denied" Errors in Container Logs

If you see permission errors in container logs:

1. Check the logs to identify the exact path with permission issues:
   ```bash
   nomad alloc logs <alloc-id>
   ```

2. Connect to the container and check permissions:
   ```bash
   nomad alloc exec <alloc-id> ls -la /path/in/container
   ```

3. Adjust permissions on the host:
   ```bash
   sudo chmod -R 777 /volume1/docker/nomad/volumes/service_data
   ```

4. If needed, run the container as a specific user:
   ```hcl
   config {
     image = "service-image:latest"
     
     # Add this to run as specific user
     user = "root"
     
     # Mount configuration...
   }
   ```

## Data Persistence Issues

### Data Not Persisting Between Restarts

**Issue**:
Data is lost when a container or service is restarted.

**Cause**:
The container might be writing to a non-mounted path or the volume mount is incorrect.

**Solution**:
1. Verify your service is configured to write to the correct path inside the container:
   ```bash
   # Get allocation ID
   ALLOC_ID=$(nomad job status service-name | grep running | awk '{print $1}')
   
   # Check the paths inside the container
   nomad alloc exec $ALLOC_ID ls -la /path/in/container
   ```

2. Check that the volume mount is correctly specified:
   ```bash
   nomad job status -verbose service-name | grep -A 5 mount
   ```

3. Verify data is being written to the host:
   ```bash
   ls -la /volume1/docker/nomad/volumes/service_data
   ```

4. Update your job definition with the correct mount path:
   ```hcl
   mount {
     type = "bind"
     source = "/volume1/docker/nomad/volumes/service_data"
     target = "/correct/path/in/container"
     readonly = false
   }
   ```

### Volume Path Not Found

**Issue**:
Container fails to start with errors about missing mount points.

**Cause**:
The host path specified in the volume mount doesn't exist or has a typo.

**Solution**:
1. Verify the path exists on the host:
   ```bash
   ls -la /volume1/docker/nomad/volumes/service_data
   ```

2. Create it if needed:
   ```bash
   mkdir -p /volume1/docker/nomad/volumes/service_data
   ```

3. Check your job definition for typos in the volume path:
   ```hcl
   mount {
     type = "bind"
     source = "/volume1/docker/nomad/volumes/service_data"
     target = "/container/path"
     readonly = false
   }
   ```

4. Run with verbose output to see the exact error:
   ```bash
   nomad job run -verbose job-file.hcl
   ```

## Container Manager Volume Issues

### Docker Overlay Storage Space Issues

If container manager is reporting disk space issues:

1. Check Docker storage space usage:
   ```bash
   df -h /var/packages/ContainerManager/var/docker
   ```

2. Clean up unused images:
   ```bash
   docker system prune -a
   ```

3. Check for large volumes:
   ```bash
   du -sh /volume1/docker/nomad/volumes/*
   ```

### Container Restart Loop

If a container keeps restarting with volume-related errors:

1. Check the container logs:
   ```bash
   ALLOC_ID=$(nomad job allocs -job service-name -latest | tail -n +2 | awk '{print $1}')
   nomad alloc logs $ALLOC_ID
   ```

2. Verify the volume exists and has correct permissions:
   ```bash
   ls -la /volume1/docker/nomad/volumes/service_data
   ```

3. Try a direct Docker run to isolate the issue:
   ```bash
   docker run --rm -v /volume1/docker/nomad/volumes/service_data:/container/path service-image:latest
   ```

## Synology-Specific Volume Considerations

### Managing Service UIDs/GIDs

**Issue**:
Different containers expect different user IDs, which can cause permission issues on Synology.

**Solution**:
Create a reference table of service UIDs/GIDs for quick troubleshooting:

| Service | Container UID:GID | Required Permissions |
|---------|------------------|----------------------|
| Grafana | 472:472 | 755 |
| PostgreSQL | 999:999 | 700 |
| Consul | 100:1000 | 777 |
| Prometheus | 65534:65534 | 755 |

Apply these permissions during setup or when troubleshooting:
```bash
sudo chown -R 472:472 /volume1/docker/nomad/volumes/grafana_data
sudo chmod 755 /volume1/docker/nomad/volumes/grafana_data
```

### Error: "unknown volume type" When Creating Volumes

**Issue**:
When running `nomad volume create` commands, you receive an error message:
```
Error unknown volume type:
```

**Cause**:
The Synology version of Nomad does not support the standard `host` volume type used in the `nomad volume create` command.

**Solution**:
Use the mount directive approach or Docker volume mounts:

1. Mount directive (recommended):
   ```hcl
   mount {
     type = "bind"
     source = "/volume1/docker/nomad/volumes/service_data"
     target = "/container/path"
     readonly = false
   }
   ```

2. Docker volume mounts:
   ```hcl
   volumes = [
     "/volume1/docker/nomad/volumes/service_data:/container/path"
   ]
   ```

### Migrating From Volumes Array to Mount Directive

If you're updating job files to use the new mount directive:

1. Original volumes configuration:
   ```hcl
   config {
     image = "service-image:latest"
     volumes = [
       "/volume1/docker/nomad/volumes/service_data:/container/path"
     ]
   }
   ```

2. New mount directive configuration:
   ```hcl
   config {
     image = "service-image:latest"
     mount {
       type = "bind"
       source = "/volume1/docker/nomad/volumes/service_data"
       target = "/container/path"
       readonly = false
     }
   }
   ```

3. Update and validate the job file:
   ```bash
   nomad job validate updated-job.hcl
   nomad job run updated-job.hcl
   ```

### Testing Different Volume Approaches

If you're not sure which approach works best on your Synology:

1. Create a test job with both approaches:
   ```hcl
   job "volume-test" {
     group "test1" {
       task "mount-test" {
         driver = "docker"
         config {
           image = "alpine:latest"
           command = "sh"
           args = ["-c", "echo 'Mount test successful' > /data/test.txt && sleep 300"]
           mount {
             type = "bind"
             source = "/volume1/docker/nomad/volumes/test_data"
             target = "/data"
             readonly = false
           }
         }
       }
     }
     
     group "test2" {
       task "volumes-test" {
         driver = "docker"
         config {
           image = "alpine:latest"
           command = "sh"
           args = ["-c", "echo 'Volumes test successful' > /data/test.txt && sleep 300"]
           volumes = [
             "/volume1/docker/nomad/volumes/test_data2:/data"
           ]
         }
       }
     }
   }
   ```

2. Create the test directories:
   ```bash
   mkdir -p /volume1/docker/nomad/volumes/test_data
   mkdir -p /volume1/docker/nomad/volumes/test_data2
   chmod 777 /volume1/docker/nomad/volumes/test_data
   chmod 777 /volume1/docker/nomad/volumes/test_data2
   ```

3. Run the test job and check results:
   ```bash
   nomad job run volume-test.hcl
   # After a minute
   cat /volume1/docker/nomad/volumes/test_data/test.txt
   cat /volume1/docker/nomad/volumes/test_data2/test.txt
   ```

### DSM Updates and Volume Permissions

After DSM updates, volume permissions might reset. To restore them:

1. Create a script to fix permissions:
   ```bash
   #!/bin/bash
   # fix-permissions.sh
   
   # Grafana
   chown -R 472:472 /volume1/docker/nomad/volumes/grafana_data
   chmod 755 /volume1/docker/nomad/volumes/grafana_data
   
   # Consul
   chmod 777 /volume1/docker/nomad/volumes/consul_data
   
   # Prometheus
   chown -R 65534:65534 /volume1/docker/nomad/volumes/prometheus_data
   chmod 755 /volume1/docker/nomad/volumes/prometheus_data
   
   # Add other services as needed
   ```

2. Make the script executable:
   ```bash
   chmod +x fix-permissions.sh
   ```

3. Run after DSM updates:
   ```bash
   ./fix-permissions.sh
   ```
```