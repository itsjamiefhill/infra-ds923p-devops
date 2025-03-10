# Logging Setup for Synology DS923+

This document provides detailed information about the logging stack of the HomeLab DevOps Platform for Synology DS923+.

## Overview

The logging stack consists of two main components that work together to provide a centralized logging solution:

- **Loki**: A horizontally-scalable, highly-available log aggregation system
- **Promtail**: An agent that ships the contents of local logs to Loki

This logging stack enables you to:
- Centralize logs from all platform services
- Search and filter logs across multiple services
- Correlate logs with metrics in Grafana
- Troubleshoot issues efficiently
- Maintain a historical log archive

## Architecture

The logging stack follows a simple and effective architecture:

1. **Collection**: Promtail runs on the Synology NAS and collects logs from various sources
2. **Transport**: Promtail sends logs to Loki with labels for identification
3. **Storage**: Loki stores logs efficiently using a combination of chunks and indexes
4. **Query**: Grafana or Loki's API can be used to search and retrieve logs

## Components

### Loki

Loki is the log storage and query system:

- **Role**: Stores and indexes log data
- **Storage**: Uses high_capacity volume for log data
- **Query Language**: LogQL for searching and filtering logs
- **Integration**: Built-in Grafana datasource
- **Authentication**: Integrated with OIDC via Traefik

### Promtail

Promtail is the log collection agent:

- **Role**: Discovers, tails, and ships logs to Loki
- **Deployment**: Runs on the Synology NAS
- **Sources**: System logs, Docker logs, and Nomad allocation logs
- **Labels**: Adds metadata labels to logs for easier querying
- **Integration**: Automatically sends logs to Loki

## Configuration

### Loki Configuration

Loki is configured with a YAML configuration file:

```yaml
auth_enabled: false

server:
  http_listen_port: 3100

ingester:
  lifecycler:
    address: 127.0.0.1
    ring:
      kvstore:
        store: inmemory
      replication_factor: 1
    final_sleep: 0s
  chunk_idle_period: 5m
  chunk_retain_period: 30s

schema_config:
  configs:
    - from: 2020-10-24
      store: boltdb-shipper
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 24h

storage_config:
  boltdb_shipper:
    active_index_directory: /loki/boltdb-shipper-active
    cache_location: /loki/boltdb-shipper-cache
    cache_ttl: 24h
    shared_store: filesystem
  filesystem:
    directory: /loki/chunks

limits_config:
  enforce_metric_name: false
  reject_old_samples: true
  reject_old_samples_max_age: 168h
```

### Promtail Configuration

Promtail is configured with a YAML file that defines where to find logs and how to label them:

```yaml
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://loki.service.consul:3100/loki/api/v1/push

scrape_configs:
  - job_name: system
    static_configs:
    - targets:
        - localhost
      labels:
        job: varlogs
        host: ${HOSTNAME}
        __path__: /var/log/*log

  - job_name: docker
    static_configs:
    - targets:
        - localhost
      labels:
        job: docker
        host: ${HOSTNAME}
        __path__: /var/packages/ContainerManager/var/docker/containers/*/*.log
        
  - job_name: nomad_alloc
    static_configs:
    - targets:
        - localhost
      labels:
        job: nomad
        host: ${HOSTNAME}
        __path__: /var/lib/nomad/alloc/*/*/alloc/logs/*
```

## Memory Optimization for Synology DS923+

With 32GB RAM available on your system, the logging stack is configured with generous resource allocation:

```hcl
# Loki resources
resources {
  cpu    = 1000  # 1 core
  memory = 3072  # 3 GB RAM
}

# Promtail resources
resources {
  cpu    = 200   # 0.2 cores
  memory = 256   # 256 MB RAM
}
```

These allocations provide excellent performance for your logging stack while still leaving ample resources for other services.

## Data Persistence

Loki data is persisted using a Nomad volume:

- **Volume Name**: loki_data
- **Storage Class**: high_capacity (given the size of log data)
- **Host Path**: `/volume1/nomad/volumes/high_capacity/loki_data` (default)
- **Container Path**: `/loki`

This ensures that logs are maintained across restarts and DSM updates.

## Technical Implementation

### Loki Job

Loki is deployed as a Nomad job:

```hcl
job "loki" {
  datacenters = ["dc1"]
  type = "service"

  group "logging" {
    count = 1
    
    volume "loki_data" {
      type = "host"
      read_only = false
      source = "high_capacity"
    }

    task "loki" {
      driver = "docker"
      
      volume_mount {
        volume = "loki_data"
        destination = "/loki"
        read_only = false
      }

      config {
        image = "grafana/loki:latest"
        ports = ["http"]
        
        volumes = [
          "local/loki-config.yaml:/etc/loki/local-config.yaml"
        ]
      }

      template {
        data = <<EOF
auth_enabled: false

server:
  http_listen_port: 3100

ingester:
  lifecycler:
    address: 127.0.0.1
    ring:
      kvstore:
        store: inmemory
      replication_factor: 1
    final_sleep: 0s
  chunk_idle_period: 5m
  chunk_retain_period: 30s

schema_config:
  configs:
    - from: 2020-10-24
      store: boltdb-shipper
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 24h

storage_config:
  boltdb_shipper:
    active_index_directory: /loki/boltdb-shipper-active
    cache_location: /loki/boltdb-shipper-cache
    cache_ttl: 24h
    shared_store: filesystem
  filesystem:
    directory: /loki/chunks

limits_config:
  enforce_metric_name: false
  reject_old_samples: true
  reject_old_samples_max_age: 168h
EOF
        destination = "local/loki-config.yaml"
      }

      resources {
        cpu    = 1000
        memory = 3072
      }

      service {
        name = "loki"
        port = "http"
        
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.loki.rule=Host(`loki.homelab.local`)",
          "traefik.http.routers.loki.tls=true",
          "traefik.http.routers.loki.middlewares=oidc-auth@consul",
          "homepage.name=Loki",
          "homepage.icon=loki.png",
          "homepage.group=Monitoring",
          "homepage.description=Log aggregation system"
        ]
      }
    }

    network {
      port "http" {
        static = 3100
      }
    }
  }
}
```

### Promtail Job

Promtail is deployed as a system job:

```hcl
job "promtail" {
  datacenters = ["dc1"]
  type = "system"

  group "logging" {
    task "promtail" {
      driver = "docker"
      
      config {
        image = "grafana/promtail:latest"
        network_mode = "host"
        
        volumes = [
          "local/promtail-config.yaml:/etc/promtail/config.yml",
          "/var/log:/var/log",
          "/var/packages/ContainerManager/var/docker/containers:/var/packages/ContainerManager/var/docker/containers:ro",
          "/var/lib/nomad:/var/lib/nomad:ro"
        ]
      }

      template {
        data = <<EOF
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://loki.service.consul:3100/loki/api/v1/push

scrape_configs:
  - job_name: system
    static_configs:
    - targets:
        - localhost
      labels:
        job: varlogs
        host: ${HOSTNAME}
        __path__: /var/log/*log

  - job_name: docker
    static_configs:
    - targets:
        - localhost
      labels:
        job: docker
        host: ${HOSTNAME}
        __path__: /var/packages/ContainerManager/var/docker/containers/*/*.log
        
  - job_name: nomad_alloc
    static_configs:
    - targets:
        - localhost
      labels:
        job: nomad
        host: ${HOSTNAME}
        __path__: /var/lib/nomad/alloc/*/*/alloc/logs/*
EOF
        destination = "local/promtail-config.yaml"
      }

      resources {
        cpu    = 200
        memory = 256
      }

      service {
        name = "promtail"
        port = "9080"
      }
    }
  }
}
```

## Accessing Logs

### Grafana Integration

The primary way to access logs is through Grafana, which is pre-configured with a Loki datasource:

1. Open Grafana at `https://grafana.homelab.local`
2. Go to Explore
3. Select the Loki datasource
4. Use LogQL to query logs

Example LogQL queries:
- `{job="docker"}`: Shows all Docker container logs
- `{job="nomad"}`: Shows all Nomad allocation logs
- `{job="varlogs"}`: Shows all system logs
- `{container_name="consul"}`: Shows logs from the Consul container

### Loki HTTP API

You can also query Loki directly via its HTTP API:

- `https://loki.homelab.local/loki/api/v1/query`: Run LogQL queries
- `https://loki.homelab.local/loki/api/v1/labels`: List all labels
- `https://loki.homelab.local/loki/api/v1/label/<name>/values`: List values for a label

Example curl command:
```bash
curl -X POST -H "Content-Type: application/json" -d '{"query": "{job=\"docker\"}"}' https://loki.homelab.local/loki/api/v1/query
```

## Synology-Specific Log Sources

For Synology DS923+, Promtail collects logs from:

1. **DSM System Logs**: Located in `/var/log/`
2. **Container Logs**: Located in `/var/packages/ContainerManager/var/docker/containers/`
3. **Nomad Allocation Logs**: Located in `/var/lib/nomad/alloc/`
4. **Application Logs**: Any custom application logs mounted into containers

## Log Retention and Storage

By default, the logging stack is configured for a homelab environment:

- **Retention Period**: 7 days (168 hours)
- **Storage Type**: Local filesystem on high_capacity volume
- **Storage Location**: Loki data volume

These settings can be customized in the Loki configuration file based on your needs and available storage.

## Handling DSM Updates

When updating your Synology DSM:

1. The logging services will typically stop during the update
2. Log data will remain safe in the persistent volume
3. After the update, the services will restart automatically
4. Some logs during the update period may not be collected

## Integrating Application Logs

To include logs from your custom applications:

### Container Logs

If your application runs in a Docker container:
- Logs written to stdout/stderr are automatically collected
- No additional configuration needed

### File Logs

If your application writes to log files:
1. Mount the log directory into Promtail
2. Add a scrape config for your log path
3. Add appropriate labels for identification

Example Promtail configuration:
```yaml
scrape_configs:
  - job_name: my_application
    static_configs:
    - targets:
        - localhost
      labels:
        job: my_app
        environment: production
        __path__: /path/to/my/app/logs/*.log
```

## Security and Authentication

### OIDC Authentication

Loki's web interface is protected by OIDC authentication through Traefik:

```hcl
tags = [
  "traefik.http.routers.loki.middlewares=oidc-auth@consul"
]
```

### Vault Integration

Sensitive configuration values can be stored in Vault:

```hcl
template {
  data = <<EOF
{{- with secret "kv/data/loki/s3" }}
storage_config:
  aws:
    s3: s3://{{ .Data.data.region }}/{{ .Data.data.bucket }}
    access_key_id: {{ .Data.data.access_key }}
    secret_access_key: {{ .Data.data.secret_key }}
{{- end }}
EOF
  destination = "local/loki-storage.yaml"
}
```

## Backup and Recovery

### Backing Up Logs

To backup Loki data:

```bash
# Option 1: Using Synology Hyper Backup
# Include /volume1/nomad/volumes/high_capacity/loki_data in your backup task

# Option 2: Manual backup
# Stop Loki
nomad job stop loki

# Backup the data directory
tar -czf /volume2/backups/services/loki_backup.tar.gz -C /volume1/nomad/volumes/high_capacity loki_data

# Restart Loki
nomad job run jobs/loki.hcl
```

### Restoring Logs

To restore Loki data:

```bash
# Stop Loki
nomad job stop loki

# Restore the data directory
rm -rf /volume1/nomad/volumes/high_capacity/loki_data/*
tar -xzf /volume2/backups/services/loki_backup.tar.gz -C /volume1/nomad/volumes/high_capacity

# Restart Loki
nomad job run jobs/loki.hcl
```

## Troubleshooting

### Common Loki Issues

1. **Query Performance**:
   - Reduce the time range of your query
   - Add more specific label filters
   - Increase RAM allocation for Loki

2. **Missing Logs**:
   - Verify Promtail is running
   - Check Promtail scrape configurations
   - Ensure log paths are correct
   - Verify Promtail can access log files

3. **Storage Issues**:
   - Check disk space on the Loki volume
   - Adjust retention period if needed
   - Monitor chunk and index size

### Common Promtail Issues

1. **Connection to Loki**:
   - Verify Loki URL in Promtail config
   - Check network connectivity between Promtail and Loki
   - Ensure Loki is running and healthy

2. **Permission Issues**:
   - Check if Promtail can access log files
   - Ensure container has appropriate mounts
   - Verify Promtail runs with sufficient privileges

## Next Steps

After deploying the logging stack, the next step is to set up OIDC authentication for single sign-on across all services. This is covered in [OIDC Setup](09-oidc-setup.md).