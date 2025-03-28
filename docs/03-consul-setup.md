# Consul Setup for Synology DS923+

This document provides detailed information about the Consul service discovery component of the HomeLab DevOps Platform on Synology DS923+.

## Overview

Consul is a service mesh solution that enables service discovery, configuration, and segmentation functionality for the platform. It acts as the backbone for service-to-service communication and provides key-value storage for configuration.

In the HomeLab DevOps Platform, Consul is the first service deployed because other components depend on it for:
- Service discovery
- Health checking
- DNS resolution
- Key-value storage
- Service metadata for the Homepage dashboard

## Architecture

The platform implements Consul in a simplified single-server mode appropriate for a Synology homelab environment:

- **Deployment Mode**: Single server with `-bootstrap` mode
- **Service Registration**: All platform services register with Consul
- **DNS Interface**: Provides service.consul domain resolution
- **UI**: Web interface for service management
- **Metadata**: Stores service metadata for Homepage dashboard integration
- **Optional SSL**: Support for secure communication with TLS

## Synology-Specific Deployment Method

Consul is deployed as a Nomad job on Synology devices. The `03-deploy-consul.sh` script has been updated to enable Nomad deployment with SSL support while addressing Synology-specific considerations.

### Nomad Deployment Architecture

The deployment method has been improved in the following ways:

1. **Modular Script Structure**:
   - `03-deploy-consul.sh`: Main deployment script
   - `03a-consul-utils.sh`: Core utility functions
   - `03b-consul-utils.sh`: Directory and job configuration
   - `03c-consul-utils.sh`: Deployment functions
   - `03d-consul-utils.sh`: Helper functions

2. **Nomad SSL Integration**:
   - Proper support for Nomad's SSL-secured API
   - Automatic detection and configuration of SSL environment variables
   - Secure communication for all Nomad operations

3. **Improved Volume Mounting**:
   - Uses the recommended `mount` directive instead of `volumes` array
   - More explicit and flexible configuration of bind mounts
   - Better performance and compatibility with Synology's Nomad implementation

4. **Optional Consul SSL Support**:
   - Configurable TLS encryption for Consul communications
   - Integration with existing Let's Encrypt certificates
   - Secure client-server and server-server communications

5. **Authentication Handling**:
   - Proper support for Nomad tokens
   - Saves tokens in a configuration file for reuse
   - Fallback mechanisms when authentication fails

6. **Enhanced Error Handling**:
   - Comprehensive Docker permission checks
   - Automatic permission fixes where possible
   - Fallback to Docker container deployment if Nomad deployment fails

7. **Helper Scripts**:
   - `bin/start-consul.sh`: Script to start the Consul Nomad job
   - `bin/stop-consul.sh`: Script to stop the Consul Nomad job
   - `bin/consul-status.sh`: Script to check Consul status
   - `bin/consul-troubleshoot.sh`: Script for troubleshooting (available with fallback option)

### Nomad Job Configuration

The Consul Nomad job is defined with these key configurations:

```hcl
job "consul" {
  datacenters = ["dc1"]
  type        = "service"
  
  priority = 100
  
  group "consul" {
    count = 1
    
    network {
      mode = "host"
      
      port "http" {
        static = 8500
        to     = 8500
      }
      
      port "dns" {
        static = 8600
        to     = 8600
      }
      
      port "server" {
        static = 8300
        to     = 8300
      }
      
      port "serf_lan" {
        static = 8301
        to     = 8301
      }
      
      port "serf_wan" {
        static = 8302
        to     = 8302
      }
    }
    
    task "consul" {
      driver = "docker"
      
      config {
        image = "hashicorp/consul:1.15.4"
        network_mode = "host"
        
        # Use mount directive instead of volumes array
        mount {
          type = "bind"
          source = "/volume1/docker/nomad/volumes/consul_data"
          target = "/consul/data"
          readonly = false
        }
        
        # SSL configuration mounts (when enabled)
        mount {
          type = "bind"
          source = "/volume1/docker/nomad/config/consul"
          target = "/consul/config"
          readonly = true
        }
        
        mount {
          type = "bind"
          source = "/volume1/docker/nomad/volumes/certificates/consul"
          target = "/consul/config/certs"
          readonly = true
        }
        
        args = [
          "agent",
          "-server",
          "-bootstrap",
          "-bind=10.0.4.78",
          "-advertise=10.0.4.78",
          "-client=0.0.0.0",
          "-ui",
          "-config-file=/consul/config/tls.json"  # When SSL is enabled
        ]
      }
      
      resources {
        cpu    = 500
        memory = 512
      }
      
      service {
        name = "consul"
        port = "http"
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.consul.rule=Host(`consul.homelab.local`)",
          "traefik.http.routers.consul.entrypoints=web",
          "homepage.name=Consul",
          "homepage.icon=consul.png",
          "homepage.group=Infrastructure",
          "homepage.description=Service Discovery and Mesh"
        ]
        
        check {
          type     = "http"
          path     = "/v1/status/leader"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }
  }
}
```

This configuration:
- Uses host networking for proper DNS and service discovery
- Uses the `mount` directive for persistent storage and configuration
- Configures proper health checks
- Sets Traefik integration for HTTP access
- Includes metadata for the Homepage dashboard
- Supports optional SSL configuration

### Fallback Docker Method

If Nomad deployment fails, the script can generate a fallback Docker deployment method:

```bash
docker run -d \
  --name consul \
  --restart unless-stopped \
  --network host \
  -v "/volume1/docker/nomad/volumes/consul_data:/consul/data" \
  -v "/volume1/docker/nomad/config/consul:/consul/config" \
  -v "/volume1/docker/nomad/volumes/certificates/consul:/consul/config/certs" \
  hashicorp/consul:1.15.4 \
  agent -server -bootstrap \
  -bind=10.0.4.78 \
  -advertise=10.0.4.78 \
  -client=0.0.0.0 \
  -ui \
  -config-file=/consul/config/tls.json
```

This provides a reliable alternative when Nomad encounters issues, with the same SSL and volume configurations.

## Configuration

Key configuration elements for Consul include:

| Parameter | Default Value | Description |
|-----------|---------------|-------------|
| HTTP Port | 8500 | Web UI and API |
| DNS Port | 8600 | DNS interface for service discovery |
| Server Port | 8300 | Server RPC |
| Serf LAN Port | 8301 | Gossip protocol for LAN |
| Serf WAN Port | 8302 | Gossip protocol for WAN |
| Bootstrap | true | Self-elect as cluster leader |
| UI | enabled | Web interface available |
| Bind Address | AUTO | IP address to bind services to |
| Advertise Address | AUTO | IP address to advertise to other nodes |
| Enable SSL | false | Enable TLS encryption (configurable) |

### SSL Configuration

To enable SSL for Consul, you can set the following variable in your `custom.conf`:

```bash
CONSUL_ENABLE_SSL=true  # Default is false
```

When SSL is enabled:
1. The script will copy your Let's Encrypt certificates to the proper location
2. A TLS configuration file will be created for Consul
3. The job definition will include the necessary mounts and arguments
4. Helper scripts will be updated to support SSL functionality

The script expects the following certificate files to exist in the `./certs` directory:
- `fullchain.pem` - Used as the CA certificate
- `cert.pem` - Used as the server certificate
- `privkey.pem` - Used as the server private key

## Data Persistence

Consul data is persisted on the Synology NAS using a mounted volume:
- **Host Path**: `/volume1/docker/nomad/volumes/consul_data` (default)
- **Container Path**: `/consul/data`

This ensures that Consul's state, including service registrations and key-value pairs, is maintained across restarts and DSM updates.

The use of the `mount` directive in the Nomad job definition provides better compatibility and performance than the older volumes approach.

## DNS Integration on Synology

### Hosts File Method

Since Synology DSM doesn't use dnsmasq by default for DNS resolution, the most reliable method for DNS integration is to add an entry to the `/etc/hosts` file:

```bash
# Add consul.service.consul to hosts file
PRIMARY_IP=$(get_primary_ip)
sudo sed -i '/consul\.service\.consul/d' /etc/hosts  # Remove any existing entry
echo "${PRIMARY_IP} consul.service.consul" | sudo tee -a /etc/hosts
```

This allows local resolution of the `consul.service.consul` domain on the Synology device itself.

### Optional dnsmasq Configuration

If dnsmasq is available and configured on your Synology, you can also set up forwarding of .consul domains:

```bash
# If dnsmasq is available
if command -v dnsmasq &>/dev/null; then
  sudo mkdir -p /etc/dnsmasq.conf.d
  echo "server=/consul/127.0.0.1#8600" | sudo tee /etc/dnsmasq.conf.d/10-consul
  # Attempt to restart dnsmasq (may not work on all Synology models)
  sudo systemctl restart dnsmasq 2>/dev/null || true
fi
```

### Network-Wide DNS Resolution

For network-wide resolution of `.consul` domains, consider one of these approaches:

1. **Router DNS Configuration**:
   - Add DNS forwarding in your router to send `.consul` domains to your Synology IP
   - Configure conditional forwarding for the `.consul` domain

2. **Host Entries on Clients**:
   - Add entries to `/etc/hosts` (or equivalent) on client machines

3. **Local DNS Server**:
   - Run a dedicated DNS server with proper forwarding rules
   - Configure clients to use this DNS server

## Service Registration

Other services in the platform register themselves with Consul, enabling:

1. **Service Discovery**: Services can find each other by name
2. **Health Checking**: Consul monitors service health
3. **DNS Resolution**: Services are accessible via DNS (service.service.consul)
4. **Metadata Exchange**: Services can advertise capabilities through tags
5. **Homepage Integration**: Services provide display metadata for the dashboard

For example, this is how Traefik discovers services to route:

```hcl
[providers.consulCatalog]
  prefix = "traefik"
  exposedByDefault = false
  
  [providers.consulCatalog.endpoint]
    address = "127.0.0.1:8500"
    scheme = "http"
```

## Nomad SSL Integration

The deployment scripts now fully support Nomad with SSL enabled:

1. **Environment Variables**: 
   ```bash
   export NOMAD_ADDR=https://127.0.0.1:4646
   export NOMAD_CACERT=/var/packages/nomad/shares/nomad/etc/certs/nomad-ca.pem
   export NOMAD_CLIENT_CERT=/var/packages/nomad/shares/nomad/etc/certs/nomad-cert.pem
   export NOMAD_CLIENT_KEY=/var/packages/nomad/shares/nomad/etc/certs/nomad-key.pem
   ```

2. **Authentication**: Nomad tokens are securely stored and loaded when needed

3. **API Access**: All API calls use proper SSL certificate verification

4. **Helper Scripts**: All scripts are configured for SSL by default

## Homepage Dashboard Integration

For the Homepage dashboard, services register with additional metadata:

```hcl
service {
  name = "grafana"
  port = "http"
  
  tags = [
    "traefik.enable=true",
    "traefik.http.routers.grafana.rule=Host(`grafana.homelab.local`)",
    "homepage.name=Grafana",
    "homepage.icon=grafana.png",
    "homepage.group=Monitoring",
    "homepage.description=Metrics and dashboard visualization"
  ]
}
```

These tags allow Homepage to automatically discover and categorize services for display.

## Accessing Consul

You can access Consul through multiple interfaces:

1. **Web UI**: `http://consul.homelab.local` or `http://your-synology-ip:8500`
2. **HTTP API**: `http://your-synology-ip:8500/v1/...`
3. **DNS Interface**: Direct query to consul DNS `dig @127.0.0.1 -p 8600 <service>.service.consul`
4. **Command Line**: Using the Consul CLI (if installed)
5. **Host Entry**: If you've added the hosts file entry, simply `http://consul.service.consul:8500`

When SSL is enabled, HTTPS endpoints are also available.

## Memory Optimization for Synology

Since the DS923+ has 32GB RAM, you can optimize Consul's memory usage:

```bash
# In your custom.conf file:
CONSUL_MEMORY=1024  # 1GB RAM
```

This provides ample memory for Consul while leaving resources for other services.

## Security Considerations

The default setup is optimized for ease of use in a homelab environment. For enhanced security:

1. **Enable SSL**: Set `CONSUL_ENABLE_SSL=true` in your custom.conf
2. **Integration with Vault**: Configure Consul to use Vault for secret storage
3. **Enable ACLs**: Configure access control lists
4. **Set Agent Tokens**: Use tokens for agent communications

To implement these enhancements, add the appropriate configuration to your `custom.conf` file.

## Scaling Considerations

While the default setup uses a single Consul server, you can scale to a multi-server cluster if needed in the future:

1. Modify the container deployment to join existing servers
2. Set appropriate bootstrap settings
3. Configure retry_join for server discovery

For most Synology homelab setups, a single server is sufficient.

## Key Consul Commands

Useful Consul commands for administration:

- **View Consul logs**: `sudo docker logs consul` (Docker) or `nomad alloc logs <alloc-id>` (Nomad)
- **Restart Consul**: `${SCRIPT_DIR}/bin/stop-consul.sh && ${SCRIPT_DIR}/bin/start-consul.sh`
- **List services**: `curl http://localhost:8500/v1/catalog/services`
- **View nodes**: `curl http://localhost:8500/v1/catalog/nodes`
- **Check service health**: `curl http://localhost:8500/v1/health/service/<service-name>`
- **List KV pairs**: `curl http://localhost:8500/v1/kv/?recurse`
- **Store KV pair**: `curl -X PUT -d '<value>' http://localhost:8500/v1/kv/<key>`

## Monitoring Consul

Consul's status can be monitored through:

1. **Prometheus**: Configured to scrape Consul metrics
2. **Grafana**: Dashboards available for visualizing metrics
3. **Consul UI**: Real-time status of services and nodes
4. **Nomad logs**: `nomad alloc logs <alloc-id>` for the consul job
5. **Homepage Dashboard**: High-level status display
6. **Helper Script**: `${SCRIPT_DIR}/bin/consul-status.sh` for quick status checks

## Handling DSM Updates

When updating your Synology DSM:

1. Consul should restart automatically via Nomad
2. Data will persist in the mapped volume
3. After an update, verify hosts file integration still works:
   ```bash
   # If hosts file entry is missing, restore it
   echo "10.0.4.78 consul.service.consul" | sudo tee -a /etc/hosts
   ```

4. Verify Consul is running:
   ```bash
   ${SCRIPT_DIR}/bin/consul-status.sh
   ```

5. If needed, restart Consul:
   ```bash
   ${SCRIPT_DIR}/bin/stop-consul.sh && ${SCRIPT_DIR}/bin/start-consul.sh
   ```

## Using Consul in Your Applications

You can leverage Consul from your own applications deployed to the platform:

1. **Service Registration**: Register your service with Consul
2. **Service Discovery**: Look up other services by name
3. **Key-Value Storage**: Store and retrieve configuration
4. **Health Checking**: Register health checks for your service
5. **Homepage Integration**: Add metadata for dashboard display

## Troubleshooting

Common issues and their solutions:

1. **"Permission denied" When Running Nomad Job**:
   - **Cause**: The nomad user doesn't have the necessary permissions to access Docker
   - **Solution**: Fix Docker permissions
     ```bash
     sudo synogroup --add docker  # create docker group if needed
     sudo synogroup --member docker nomad  # add nomad user to docker group
     sudo chown root:docker /var/run/docker.sock  # fix socket permissions
     ```
   - Then restart Nomad and retry

2. **Nomad SSL Certificate Issues**:
   - **Cause**: SSL certificates not found or permissions issues
   - **Solution**: Verify environment variables and certificate paths
     ```bash
     echo $NOMAD_CACERT
     ls -la $NOMAD_CACERT
     sudo chmod 644 $NOMAD_CACERT  # Ensure cert is readable
     ```

3. **Consul SSL Configuration Failure**:
   - **Cause**: Let's Encrypt certificates not found or copied correctly
   - **Solution**: Verify certificates exist and are readable
     ```bash
     ls -la ${SCRIPT_DIR}/certs/
     ls -la ${DATA_DIR}/certificates/consul/
     # Manually copy if needed
     sudo cp ${SCRIPT_DIR}/certs/fullchain.pem ${DATA_DIR}/certificates/consul/ca.pem
     ```

4. **"unknown volume type: host" Error**:
   - **Cause**: Synology Nomad doesn't support host volume type registration
   - **Solution**: The updated script uses the `mount` directive instead of volumes

5. **Data Not Persisting**:
   - Verify the mount path in the job definition is correct
   - Check that the host directory exists with proper permissions
   - Ensure the container is writing to the mounted path

6. **Permission Issues**:
   - Verify container user has access to the mounted directory
   - Check if ownership is set correctly on the host: `sudo chown -R <uid>:<gid> $DATA_DIR/consul_data`
   - Ensure that the required permissions are applied to the volume

7. **Cannot Access Volume Data**:
   - Check if the directory exists: `ls -la $DATA_DIR/consul_data`
   - Verify the path in your job definition
   - Check for typos in the mount path

8. **Nomad Authentication Failures**:
   - Ensure your Nomad token has appropriate permissions
   - Check that the token is valid and not expired
   - Use the proper authentication method for your Nomad setup

## Uninstallation

To uninstall Consul:

1. **Stop and Remove Container/Job**:
   ```bash
   ${SCRIPT_DIR}/bin/stop-consul.sh
   ```

2. **Remove Data (Optional)**:
   ```bash
   sudo rm -rf ${DATA_DIR}/consul_data
   ```

3. **Remove DNS Integration**:
   ```bash
   sudo sed -i '/consul\.service\.consul/d' /etc/hosts
   sudo rm -f /etc/dnsmasq.conf.d/10-consul
   ```

4. **Remove Helper Scripts**:
   ```bash
   rm -f ${PARENT_DIR}/bin/start-consul.sh
   rm -f ${PARENT_DIR}/bin/stop-consul.sh
   rm -f ${PARENT_DIR}/bin/consul-status.sh
   ```

For complete uninstallation, you can also use the updated `uninstall.sh` script which now properly handles Consul cleanup.

## Next Steps

After deploying Consul, the next step is to set up Traefik for reverse proxy functionality. This is covered in [Traefik Setup](04-traefik-setup.md).