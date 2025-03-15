# Docker vs Nomad Deployment on Synology

This document compares the direct Docker deployment approach with Nomad job deployment for services on Synology NAS systems. It provides guidance on when to use each approach based on our experience deploying the HomeLab DevOps Platform.

## Table of Contents

1. [Overview](#overview)
2. [Nomad Deployment Approach](#nomad-deployment-approach)
   - [How Nomad Works](#how-nomad-works)
   - [Advantages](#advantages-of-nomad)
   - [Limitations on Synology](#limitations-of-nomad-on-synology)
3. [Direct Docker Deployment Approach](#direct-docker-deployment-approach)
   - [How Docker Direct Deployment Works](#how-docker-direct-deployment-works)
   - [Advantages](#advantages-of-docker-direct)
   - [Limitations](#limitations-of-docker-direct)
4. [When to Use Each Approach](#when-to-use-each-approach)
5. [Implementation Examples](#implementation-examples)
6. [Migration Between Approaches](#migration-between-approaches)
7. [Best Practices](#best-practices)
8. [Troubleshooting](#troubleshooting)

## Overview

The HomeLab DevOps Platform can deploy services using two different methods:

1. **Nomad Job Deployment**: Uses Nomad's scheduler to manage the container lifecycle
2. **Direct Docker Deployment**: Uses Docker commands directly, bypassing Nomad

While the original design of the platform favors Nomad for most services, some core infrastructure components (particularly Consul) may benefit from direct Docker deployment on Synology systems due to specific constraints and requirements.

## Nomad Deployment Approach

### How Nomad Works

Nomad is a workload orchestrator that deploys and manages applications. On Synology, Nomad typically:

1. Reads a job specification (HCL format)
2. Evaluates resource requirements and constraints
3. Plans and executes the deployment
4. Manages the lifecycle of containers through the Docker driver
5. Provides health monitoring and automatic recovery

A basic Nomad job definition for Synology looks like this:

```hcl
job "service-name" {
  datacenters = ["dc1"]
  type = "service"

  group "service-group" {
    count = 1

    network {
      port "http" {
        static = 8080
      }
    }

    task "service-task" {
      driver = "docker"

      config {
        image = "service-image:latest"
        ports = ["http"]
        
        mount {
          type = "bind"
          source = "/volume1/docker/nomad/volumes/service_data"
          target = "/container/path"
          readonly = false
        }
      }

      resources {
        cpu    = 500
        memory = 512
      }
    }
  }
}
```

### Advantages of Nomad

- **Centralized Management**: All services managed through a single interface
- **Declarative Configuration**: Infrastructure defined as code
- **Service Recovery**: Automatic restart of failed services
- **Resource Controls**: CPU and memory limits enforced
- **Rolling Updates**: Zero-downtime deployments possible
- **API Integration**: Programmatic control and monitoring
- **Web UI**: Visual management and status monitoring
- **SSL Support**: Secure communication between components

### Limitations of Nomad on Synology

Synology's implementation of Nomad has several important limitations:

1. **Mount Configuration**: The Synology version of Nomad requires using either the `mount` directive or Docker-specific `volumes` configuration rather than Nomad's volume registration system
2. **Network Mode Restrictions**: Some network modes (like host networking) may not work properly through Nomad on Synology
3. **Permission Handling**: Container-to-host permission mapping can be problematic
4. **Multiple Network Interfaces**: Nomad may not correctly handle binding on systems with multiple network interfaces
5. **Resource Constraints**: Strict enforcement of resource limits may cause issues with some services
6. **Driver Constraints**: Some Docker features may not be fully supported through Nomad's Docker driver

## Direct Docker Deployment Approach

### How Docker Direct Deployment Works

Direct Docker deployment bypasses Nomad and interacts with Docker directly:

1. Uses `docker` commands to create and manage containers
2. Typically wrapped in shell scripts for easier management
3. Uses Docker's native features for volume mounting, networking, etc.
4. Relies on Docker's restart policies for recovery

A basic Docker direct deployment script looks like this:

```bash
#!/bin/bash
# start-service.sh

# Stop and remove any existing container
sudo docker stop service-name 2>/dev/null || true
sudo docker rm service-name 2>/dev/null || true

# Start new container
sudo docker run -d --name service-name \
  --restart always \
  --network host \
  -v /volume1/docker/nomad/volumes/service_data:/container/path \
  -p 8080:8080 \
  service-image:latest
```

### Advantages of Docker Direct

- **Full Docker Feature Set**: Access to all Docker features and options
- **Network Control**: Direct control over container networking (especially host mode)
- **Simplicity**: No intermediate layer between command and execution
- **Reliability**: Fewer moving parts in the deployment process
- **Troubleshooting**: Easier to diagnose issues with direct Docker commands
- **Startup Control**: Can be integrated with Synology's Task Scheduler for system boot
- **Performance**: Potentially lower overhead without the Nomad scheduling layer

### Limitations of Docker Direct

- **Manual Management**: No centralized management UI (unless using Synology's Container Manager)
- **No Orchestration**: Missing Nomad's scheduling and orchestration features
- **Script Maintenance**: Shell scripts need to be maintained and versioned
- **Limited Recovery**: Relies on Docker's restart policies rather than Nomad's more sophisticated recovery
- **Resource Controls**: Resource limits must be set through Docker flags
- **No Rolling Updates**: More complex to implement zero-downtime deployments

## When to Use Each Approach

### Use Direct Docker Deployment For:

1. **Core Infrastructure Services**:
   - Consul (especially if DNS and service discovery are critical)
   - Services that other components depend on during startup

2. **Network-Sensitive Services**:
   - Services requiring host network mode
   - Services with complex port mappings
   - Services that bind to specific network interfaces

3. **Problematic Services**:
   - Services that consistently fail when deployed through Nomad
   - Services with specific Docker requirements not supported by Nomad

4. **Systems with Multiple Network Interfaces**:
   - When specific binding control is required

### Use Nomad Deployment For:

1. **Standard Applications**:
   - Web applications
   - Databases
   - Monitoring tools
   - Most microservices

2. **Services Benefiting from Orchestration**:
   - Services requiring careful scheduling
   - Services with dependencies and ordering requirements
   - Services that benefit from rolling updates

3. **Resource-Intensive Applications**:
   - Applications needing careful resource controls
   - Applications that might compete for resources

4. **Applications Requiring Frequent Updates**:
   - Services under active development
   - Services with frequent version upgrades

## Implementation Examples

### Consul Deployment Comparison

#### Nomad Job (Using Mount Directive):

```hcl
job "consul" {
  datacenters = ["dc1"]
  type = "service"

  group "consul" {
    count = 1

    network {
      port "http" { static = 8500 }
      port "dns" { static = 8600 }
    }

    task "consul" {
      driver = "docker"

      config {
        image = "hashicorp/consul:1.15.4"
        ports = ["http", "dns"]
        
        mount {
          type = "bind"
          source = "/volume1/docker/nomad/volumes/consul_data"
          target = "/consul/data"
          readonly = false
        }
        
        command = "agent"
        args = [
          "-server",
          "-bootstrap",
          "-ui",
          "-client=0.0.0.0",
          "-data-dir=/consul/data"
        ]
      }

      resources {
        cpu    = 500
        memory = 512
      }
    }
  }
}
```

#### Direct Docker Deployment (More Reliable on Synology):

```bash
#!/bin/bash
# start-consul.sh

# Get the primary IP
PRIMARY_IP=$(ip route get 1 | awk '{print $7;exit}' 2>/dev/null || hostname -I | awk '{print $1}')
if [ -z "$PRIMARY_IP" ]; then
  echo "Error: Could not determine primary IP address"
  exit 1
fi

# Stop and remove any existing container
sudo docker stop consul 2>/dev/null || true
sudo docker rm consul 2>/dev/null || true

# Start new container
sudo docker run -d --name consul \
  --restart always \
  --network host \
  -v /volume1/docker/nomad/volumes/consul_data:/consul/data \
  hashicorp/consul:1.15.4 \
  agent -server -bootstrap \
  -bind=$PRIMARY_IP \
  -advertise=$PRIMARY_IP \
  -client=0.0.0.0 \
  -ui
```

### Prometheus Deployment Example

#### Nomad Job (Using Mount Directive):

```hcl
job "prometheus" {
  datacenters = ["dc1"]
  type = "service"

  group "prometheus" {
    count = 1

    network {
      port "http" { static = 9090 }
    }

    task "prometheus" {
      driver = "docker"

      config {
        image = "prom/prometheus:latest"
        ports = ["http"]
        
        mount {
          type = "bind"
          source = "/volume1/docker/nomad/volumes/prometheus_data"
          target = "/prometheus"
          readonly = false
        }
        
        mount {
          type = "bind"
          source = "/volume1/docker/nomad/config/prometheus.yml"
          target = "/etc/prometheus/prometheus.yml"
          readonly = true
        }
      }

      resources {
        cpu    = 1000
        memory = 1024
      }
    }
  }
}
```

## Migration Between Approaches

### From Nomad to Direct Docker

If you need to migrate a service from Nomad to direct Docker:

1. **Export Configuration**:
   ```bash
   nomad job inspect <job-name> > job-config.hcl
   ```

2. **Stop Nomad Job**:
   ```bash
   nomad job stop <job-name>
   ```

3. **Create Docker Script**:
   ```bash
   # Extract relevant configuration from job-config.hcl
   # Create start-service.sh script with appropriate Docker commands
   ```

4. **Preserve Data**:
   ```bash
   # Ensure volume paths match between Nomad and Docker
   ```

5. **Start Direct Container**:
   ```bash
   ./start-service.sh
   ```

6. **Set Up Auto-Start**:
   - Configure Synology Task Scheduler for boot-time execution

### From Direct Docker to Nomad

To migrate in the opposite direction:

1. **Create Nomad Job Definition**:
   ```bash
   # Create job-name.hcl based on Docker configuration
   ```

2. **Stop Docker Container**:
   ```bash
   sudo docker stop service-name
   sudo docker rm service-name
   ```

3. **Deploy Nomad Job**:
   ```bash
   nomad job run job-name.hcl
   ```

4. **Verify Deployment**:
   ```bash
   nomad job status job-name
   ```

5. **Remove Startup Tasks**:
   - Remove any Task Scheduler entries for the service

## Best Practices

### For Direct Docker Deployments

1. **Script Organization**:
   - Store all scripts in a consistent location (e.g., `/volume1/docker/nomad/bin/`)
   - Create both start and stop scripts for each service
   - Add version information and documentation to scripts

2. **Volume Management**:
   - Use the same volume paths as you would with Nomad
   - Set appropriate permissions before container start
   - Back up volumes regularly

3. **Logging**:
   - Configure proper logging in containers
   - Consider using Docker's logging drivers
   - Direct logs to the same locations used by Nomad

4. **Recovery**:
   - Always use `--restart always` for critical services
   - Set up Synology Task Scheduler for boot-time execution
   - Create monitoring to ensure services are running

5. **Network Management**:
   - Use `--network host` for services with complex networking
   - Explicitly bind to the primary IP when needed
   - Document port usage to avoid conflicts

### For Nomad Deployments

1. **Job Organization**:
   - Maintain job definitions in a version-controlled repository
   - Use consistent naming conventions
   - Group related services in logical ways

2. **Resource Allocation**:
   - Set appropriate CPU and memory limits
   - Monitor resource usage and adjust as needed
   - Avoid over-allocation on single-node deployments

3. **Service Integration**:
   - Use Consul for service discovery
   - Implement proper health checks
   - Set up proper dependencies between services

4. **Update Strategy**:
   - Configure appropriate update stanzas for zero-downtime deployments
   - Test update procedures before applying to production

5. **SSL Configuration**:
   - Ensure scripts set the proper environment variables for SSL
   - Include Nomad token configuration for authenticated API calls
   - Test job deployments with SSL to verify proper operation

## Troubleshooting

### Common Direct Docker Issues

1. **Container Won't Start**:
   ```bash
   # Check logs
   sudo docker logs service-name
   
   # Verify volume permissions
   ls -la /volume1/docker/nomad/volumes/service_data
   
   # Check port conflicts
   sudo ss -tulpn | grep <port>
   ```

2. **Network Binding Issues**:
   ```bash
   # For "Multiple private IPv4 addresses found" error
   # Explicitly set bind address
   -bind=$(hostname -I | awk '{print $1}')
   ```

3. **Container Keeps Restarting**:
   ```bash
   # Check logs
   sudo docker logs service-name
   
   # Check resource constraints
   sudo docker stats
   ```

### Common Nomad Issues

1. **Job Won't Start**:
   ```bash
   # Check job status
   nomad job status <job-name>
   
   # Check allocation
   nomad alloc status <alloc-id>
   
   # Check client logs
   journalctl -u nomad
   ```

2. **Resource Constraints**:
   ```bash
   # If job fails due to resources
   # Modify resources in job definition
   resources {
     cpu    = 1000  # Increase as needed
     memory = 1024  # Increase as needed
   }
   ```

3. **Mount Issues**:
   ```bash
   # If mount directive doesn't work
   # Try the alternative volumes approach
   volumes = [
     "/host/path:/container/path"
   ]
   ```

4. **SSL Certificate Issues**:
   ```bash
   # Verify environment variables are set
   echo $NOMAD_ADDR
   echo $NOMAD_CACERT
   
   # Check certificate paths
   ls -la $NOMAD_CACERT $NOMAD_CLIENT_CERT $NOMAD_CLIENT_KEY
   
   # Test SSL connectivity
   curl --cacert $NOMAD_CACERT --cert $NOMAD_CLIENT_CERT --key $NOMAD_CLIENT_KEY https://127.0.0.1:4646/v1/agent/members
   ```

5. **Authentication Issues**:
   ```bash
   # Make sure NOMAD_TOKEN is set
   echo $NOMAD_TOKEN
   
   # Test token validity
   curl -H "X-Nomad-Token: $NOMAD_TOKEN" --cacert $NOMAD_CACERT https://127.0.0.1:4646/v1/jobs
   ```
Here's the continuation of the updated `docs/docker-vs-nomad.md` file:

6. **Network Mode Issues**:
   ```bash
   # If host network mode doesn't work in Nomad
   # Consider switching to direct Docker deployment
   ```

7. **Job Definition Errors**:
   ```bash
   # Validate the job file
   nomad job validate job-file.hcl
   
   # Run with verbose output
   nomad job run -verbose job-file.hcl
   ```

8. **Mount vs Volumes Confusion**:
   ```bash
   # If you're unsure which approach to use, try the mount directive first
   mount {
     type = "bind"
     source = "/volume1/docker/nomad/volumes/service_data"
     target = "/container/path"
     readonly = false
   }
   
   # If that fails, fall back to volumes syntax
   volumes = [
     "/volume1/docker/nomad/volumes/service_data:/container/path"
   ]
   ```

## SSL Configuration for Nomad

When interacting with Nomad in scripts or from the command line, you'll need proper SSL configuration:

### Environment Variables for SSL

```bash
# Add these to your .bashrc or script
export NOMAD_ADDR=https://127.0.0.1:4646
export NOMAD_CACERT=/var/packages/nomad/shares/nomad/etc/certs/nomad-ca.pem
export NOMAD_CLIENT_CERT=/var/packages/nomad/shares/nomad/etc/certs/nomad-cert.pem
export NOMAD_CLIENT_KEY=/var/packages/nomad/shares/nomad/etc/certs/nomad-key.pem
```

### Authentication Token

```bash
# Store the token securely
echo 'NOMAD_TOKEN="your-management-token"' > /volume1/docker/nomad/config/nomad_auth.conf
chmod 600 /volume1/docker/nomad/config/nomad_auth.conf

# Load the token in scripts
if [ -f "/volume1/docker/nomad/config/nomad_auth.conf" ]; then
  source "/volume1/docker/nomad/config/nomad_auth.conf"
  export NOMAD_TOKEN
fi
```

### Nomad API Interaction with SSL

```bash
# When making API calls to Nomad, include both SSL and token
curl -H "X-Nomad-Token: $NOMAD_TOKEN" \
     --cacert $NOMAD_CACERT \
     --cert $NOMAD_CLIENT_CERT \
     --key $NOMAD_CLIENT_KEY \
     https://127.0.0.1:4646/v1/jobs
```

## Choosing the Right Approach for Synology

When deciding between Nomad and direct Docker deployment, consider:

### Use Nomad When:
- You want centralized management of most services
- You need sophisticated orchestration features
- The service doesn't have complex networking requirements
- You're comfortable with HCL syntax and Nomad's abstractions
- You want to leverage the Nomad UI for monitoring and management

### Use Direct Docker When:
- The service is part of core infrastructure (like Consul)
- You've experienced persistent issues using Nomad
- The service requires host networking or specialized Docker features
- You need more direct control over container execution
- Troubleshooting becomes easier with direct Docker commands

### Hybrid Approach

For many Synology deployments, a hybrid approach works best:

1. **Use Direct Docker** for core infrastructure:
   - Consul service discovery
   - DNS services
   - Network-critical components

2. **Use Nomad** for most application services:
   - Web applications and dashboards
   - Databases and storage services
   - Monitoring and logging components
   - Registry and other supporting services

This approach combines the reliability of direct Docker for foundational services with the management benefits of Nomad for the majority of your applications.

## Conclusion

Both Nomad and direct Docker deployment have their place in a Synology-based HomeLab DevOps platform. Understanding the strengths and limitations of each approach will help you make the best choice for each component of your infrastructure.

Remember that many issues with Nomad on Synology can be addressed by using the `mount` directive in job definitions rather than traditional Nomad volumes. When combined with proper SSL configuration, this approach provides a robust and secure orchestration layer for your containerized services.