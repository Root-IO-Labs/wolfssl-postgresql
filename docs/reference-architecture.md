# PostgreSQL FIPS Reference Architecture

**Document Version:** 1.0
**Last Updated:** 2025-12-03
**Purpose:** Production Deployment Guidance for FIPS/FedRAMP Environments

---

## 1. Overview

This document provides reference architectures for deploying the PostgreSQL 17.6 FIPS-enabled container in production environments requiring FIPS 140-3 compliance and FedRAMP authorization.

### 1.1 Scope

- Production deployment patterns
- Infrastructure requirements
- Network architecture
- High availability configurations
- Disaster recovery
- Security controls
- Monitoring and operations
- Compliance maintenance

### 1.2 Target Audience

- Cloud Architects
- Infrastructure Engineers
- Security Teams
- DevOps/SRE Teams
- Compliance Officers

---

## 2. Core Architecture Principles

### 2.1 FIPS Compliance by Design

All architectures must maintain:

✅ **FIPS Boundary Integrity**
- Container operates within validated OE
- No non-FIPS crypto paths available
- Runtime validation enforced

✅ **Fail-Closed Security**
- Container won't start if FIPS validation fails
- No graceful degradation to non-FIPS mode
- Explicit error reporting

✅ **Audit Trail**
- All FIPS validation logged
- Cryptographic operations traceable
- Compliance evidence retained

---

## 3. Infrastructure Requirements

### 3.1 Host Operating System Requirements

**Mandatory Requirements:**

| Component | Requirement | Verification |
|-----------|-------------|--------------|
| **Kernel** | >= 6.8.x | `uname -r` |
| **Architecture** | x86_64 (amd64) | `uname -m` |
| **CPU Features** | RDRAND (recommended) | `grep rdrand /proc/cpuinfo` |
| **OS** | Ubuntu 22.04/24.04, RHEL 9, or compatible | `lsb_release -a` |

**Compatibility Matrix:**

| Host OS | Kernel | Status | Notes |
|---------|--------|--------|-------|
| Ubuntu 22.04 LTS | 6.8.x+ | ✅ Validated | Recommended |
| Ubuntu 22.04 LTS (HWE) | 6.8.x+ | ✅ Supported | Use HWE kernel |
| RHEL 9.x | 5.14.x+ | ⚠️ Verify | Check wolfSSL CMVP OE |
| Amazon Linux 2023 | 6.1.x+ | ⚠️ Verify | Check kernel version |
| Debian 12 | 6.1.x+ | ⚠️ Verify | May need kernel upgrade |

**Action:** Always verify host kernel against wolfSSL CMVP OE list before deployment.

---

### 3.2 Hardware Requirements

**Minimum Production Configuration:**

| Resource | Minimum | Recommended | Notes |
|----------|---------|-------------|-------|
| **CPU** | 4 cores | 8 cores | x86_64 with RDRAND |
| **RAM** | 8 GB | 16+ GB | Plus PostgreSQL working set |
| **Storage** | 100 GB SSD | 500+ GB NVMe | For data + WAL |
| **Network** | 1 Gbps | 10 Gbps | Depending on workload |

**Storage Considerations:**
- **Data Volume:** Sized for database + growth
- **WAL Volume:** 10-20% of data volume
- **Backup Volume:** 2-3x data volume
- **IOPS:** 1000+ for production workloads

---

### 3.3 Container Runtime Requirements

**Supported Runtimes:**

| Runtime | Version | Status | Notes |
|---------|---------|--------|-------|
| **Docker** | 20.10+ | ✅ Validated | BuildKit required for build |
| **containerd** | 1.6+ | ✅ Supported | Via Docker or Kubernetes |
| **Kubernetes** | 1.24+ | ✅ Supported | See Section 5 |
| **Podman** | 4.0+ | ⚠️ Untested | Should work, not validated |

**Required Docker Configuration:**
```yaml
{
  "features": {
    "buildkit": true
  },
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
```

---

## 4. Deployment Architectures

### 4.1 Architecture 1: Single-Node Development/Testing

**Use Case:** Development, testing, CI/CD pipelines

**Diagram:**
```
┌─────────────────────────────────────┐
│      Host (Ubuntu 22.04)            │
│      Kernel: 6.8.x, x86_64         │
│                                     │
│  ┌───────────────────────────────┐ │
│  │  PostgreSQL FIPS Container    │ │
│  │                               │ │
│  │  - Port: 5432                 │ │
│  │  - Volume: /bitnami/postgresql│ │
│  │  - FIPS Validation: ✓         │ │
│  └───────────────────────────────┘ │
│             │                       │
│             ↓                       │
│  /data/postgresql (Host Volume)    │
└─────────────────────────────────────┘
```

**Deployment Command:**
```bash
docker run -d \
  --name postgresql-fips \
  --restart=unless-stopped \
  -p 5432:5432 \
  -e POSTGRESQL_PASSWORD=secure_password \
  -e POSTGRESQL_DATABASE=appdb \
  -v /data/postgresql:/bitnami/postgresql \
  postgresql-fips-ubuntu:17.6.0
```

**Characteristics:**
- ✅ Simple deployment
- ✅ Fast startup
- ✅ Development/testing suitable
- ❌ No high availability
- ❌ Not production-ready

**Security Controls:**
- Firewall rules limiting access to 5432
- Strong password enforcement
- Regular backups to separate storage
- FIPS validation on every start

---

### 4.2 Architecture 2: Single-Node Production with Backup

**Use Case:** Small production deployments, single-tenant applications

**Diagram:**
```
┌──────────────────────────────────────────────────────┐
│              Host (Ubuntu 22.04)                     │
│                                                      │
│  ┌────────────────────────────────────────────────┐ │
│  │      PostgreSQL FIPS Container                 │ │
│  │                                                │ │
│  │  - Primary: 5432                              │ │
│  │  - Metrics: 9187 (postgres_exporter)          │ │
│  │  - Volumes:                                   │ │
│  │    • Data: /data/postgresql                   │ │
│  │    • WAL: /wal/postgresql                     │ │
│  │    • Backup: /backup/postgresql               │ │
│  └────────────────────────────────────────────────┘ │
│                                                      │
│  ┌────────────────────────────────────────────────┐ │
│  │      Backup Container (Cron)                   │ │
│  │  - pg_dump scheduled                           │ │
│  │  - WAL archiving                               │ │
│  └────────────────────────────────────────────────┘ │
│                                                      │
│  ┌────────────────────────────────────────────────┐ │
│  │      Monitoring (Optional)                     │ │
│  │  - Prometheus                                  │ │
│  │  - Grafana                                     │ │
│  └────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────┘
                         │
                         ↓
              ┌─────────────────────┐
              │  Remote Backup      │
              │  S3 / GCS / Azure   │
              └─────────────────────┘
```

**Docker Compose Example:**
```yaml
version: '3.8'

services:
  postgresql:
    image: postgresql-fips-ubuntu:17.6.0
    container_name: postgresql-fips
    restart: unless-stopped
    ports:
      - "5432:5432"
    environment:
      - POSTGRESQL_PASSWORD=${DB_PASSWORD}
      - POSTGRESQL_DATABASE=production_db
      - POSTGRESQL_MAX_CONNECTIONS=200
    volumes:
      - postgresql_data:/bitnami/postgresql
      - postgresql_wal:/bitnami/postgresql/wal
      - postgresql_backup:/backup
    healthcheck:
      test: ["CMD", "pg_isready", "-U", "postgres"]
      interval: 30s
      timeout: 10s
      retries: 3
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  backup:
    image: postgres:17-alpine
    container_name: postgresql-backup
    depends_on:
      - postgresql
    environment:
      - PGPASSWORD=${DB_PASSWORD}
    volumes:
      - postgresql_backup:/backup
      - ./scripts/backup.sh:/backup.sh
    command: >
      sh -c "while true; do
        sleep 86400;
        /backup.sh;
      done"

volumes:
  postgresql_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /data/postgresql
  postgresql_wal:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /wal/postgresql
  postgresql_backup:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /backup/postgresql
```

**Characteristics:**
- ✅ Production-suitable for single-tenant
- ✅ Automated backups
- ✅ Monitoring integration
- ✅ FIPS compliance maintained
- ⚠️ Single point of failure
- ❌ No automatic failover

---

### 4.3 Architecture 3: High Availability with Streaming Replication

**Use Case:** Production applications requiring HA and failover

**Diagram:**
```
┌────────────────────────────────────────────────────────┐
│                Load Balancer / HAProxy                 │
│              (Primary: 5432, Replica: 5433)            │
└─────────────┬────────────────────────┬─────────────────┘
              │                        │
    ┌─────────▼────────┐    ┌─────────▼────────┐
    │  Primary Node    │    │  Replica Node 1  │
    │  Ubuntu 22.04    │    │  Ubuntu 22.04    │
    │  Kernel 6.8.x    │    │  Kernel 6.8.x    │
    │                  │    │                  │
    │  ┌────────────┐  │    │  ┌────────────┐ │
    │  │ PostgreSQL │  │    │  │ PostgreSQL │ │
    │  │ FIPS       │  │◀───┼──│ FIPS       │ │
    │  │ (Primary)  │  │WAL │  │ (Standby)  │ │
    │  └────────────┘  │    │  └────────────┘ │
    │                  │    │                  │
    │  Data: /data/pg  │    │  Data: /data/pg │
    └──────────────────┘    └──────────────────┘
              │
    ┌─────────▼────────┐
    │  Replica Node 2  │
    │  Ubuntu 22.04    │
    │  Kernel 6.8.x    │
    │                  │
    │  ┌────────────┐  │
    │  │ PostgreSQL │  │
    │  │ FIPS       │  │
    │  │ (Standby)  │  │
    │  └────────────┘  │
    │                  │
    │  Data: /data/pg  │
    └──────────────────┘
```

**Configuration Steps:**

**1. Primary Node:**
```bash
# Start primary
docker run -d \
  --name postgresql-primary \
  --hostname pg-primary \
  -p 5432:5432 \
  -e POSTGRESQL_REPLICATION_MODE=master \
  -e POSTGRESQL_REPLICATION_USER=repl_user \
  -e POSTGRESQL_REPLICATION_PASSWORD=repl_password \
  -e POSTGRESQL_PASSWORD=admin_password \
  -v /data/postgresql-primary:/bitnami/postgresql \
  postgresql-fips-ubuntu:17.6.0
```

**2. Replica Nodes:**
```bash
# Start replica 1
docker run -d \
  --name postgresql-replica-1 \
  --hostname pg-replica-1 \
  -p 5433:5432 \
  -e POSTGRESQL_REPLICATION_MODE=slave \
  -e POSTGRESQL_REPLICATION_USER=repl_user \
  -e POSTGRESQL_REPLICATION_PASSWORD=repl_password \
  -e POSTGRESQL_MASTER_HOST=pg-primary \
  -e POSTGRESQL_MASTER_PORT_NUMBER=5432 \
  -e POSTGRESQL_PASSWORD=admin_password \
  -v /data/postgresql-replica-1:/bitnami/postgresql \
  postgresql-fips-ubuntu:17.6.0

# Repeat for replica 2 with different port and volume
```

**3. HAProxy Configuration:**
```
global
    log /dev/log local0
    maxconn 4096

defaults
    mode tcp
    timeout connect 10s
    timeout client 30s
    timeout server 30s

listen postgresql-primary
    bind *:5432
    option pgsql-check user postgres
    server primary pg-primary:5432 check

listen postgresql-replicas
    bind *:5433
    balance roundrobin
    option pgsql-check user postgres
    server replica1 pg-replica-1:5432 check
    server replica2 pg-replica-2:5432 check
```

**Characteristics:**
- ✅ High availability
- ✅ Read scaling (replicas)
- ✅ Automatic failover (with additional tooling)
- ✅ FIPS compliance on all nodes
- ✅ Production-ready
- ⚠️ Complex setup
- ⚠️ Requires monitoring and automation

---

### 4.4 Architecture 4: Kubernetes Deployment

**Use Case:** Cloud-native, microservices, orchestrated environments

**Diagram:**
```
┌──────────────────────────────────────────────────────────┐
│                   Kubernetes Cluster                      │
│                                                           │
│  ┌────────────────────────────────────────────────────┐  │
│  │              Ingress / Load Balancer                │  │
│  └──────────────────┬─────────────────────────────────┘  │
│                     │                                     │
│  ┌──────────────────▼─────────────────────────────────┐  │
│  │              Service (postgresql-svc)               │  │
│  │              ClusterIP: 5432                        │  │
│  └──────────────────┬─────────────────────────────────┘  │
│                     │                                     │
│  ┌──────────────────▼─────────────────────────────────┐  │
│  │            StatefulSet (postgresql)                 │  │
│  │                                                     │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌────────────┐ │  │
│  │  │   Pod 0     │  │   Pod 1     │  │   Pod 2    │ │  │
│  │  │  (Primary)  │  │  (Replica)  │  │  (Replica) │ │  │
│  │  │             │  │             │  │            │ │  │
│  │  │  PG FIPS    │  │  PG FIPS    │  │  PG FIPS   │ │  │
│  │  │             │  │             │  │            │ │  │
│  │  │  PVC: 100Gi │  │  PVC: 100Gi │  │  PVC:100Gi │ │  │
│  │  └─────────────┘  └─────────────┘  └────────────┘ │  │
│  └─────────────────────────────────────────────────────┘  │
│                                                           │
│  Nodes: Ubuntu 22.04, Kernel 6.8.x, x86_64              │
└──────────────────────────────────────────────────────────┘
```

**Kubernetes Manifests:**

**1. Namespace:**
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: postgresql-fips
  labels:
    fips: "enabled"
    compliance: "fedramp"
```

**2. Secret:**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: postgresql-secret
  namespace: postgresql-fips
type: Opaque
stringData:
  postgresql-password: "SecurePassword123!"
  replication-password: "ReplPassword123!"
```

**3. ConfigMap:**
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: postgresql-config
  namespace: postgresql-fips
data:
  postgresql.conf: |
    # FIPS-compliant PostgreSQL configuration
    max_connections = 200
    shared_buffers = 2GB
    effective_cache_size = 6GB
    maintenance_work_mem = 512MB
    checkpoint_completion_target = 0.9
    wal_buffers = 16MB
    default_statistics_target = 100
    random_page_cost = 1.1
    effective_io_concurrency = 200
    work_mem = 10MB
    min_wal_size = 1GB
    max_wal_size = 4GB

    # SSL/TLS (FIPS-enabled)
    ssl = on
    ssl_ciphers = 'HIGH:!aNULL:!MD5'
    ssl_prefer_server_ciphers = on

    # Logging
    log_destination = 'stderr'
    logging_collector = on
    log_directory = '/opt/bitnami/postgresql/logs'
    log_filename = 'postgresql-%Y-%m-%d.log'
    log_rotation_age = 1d
    log_rotation_size = 100MB
    log_line_prefix = '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h '
    log_timezone = 'UTC'
```

**4. StatefulSet:**
```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgresql
  namespace: postgresql-fips
spec:
  serviceName: postgresql-headless
  replicas: 3
  selector:
    matchLabels:
      app: postgresql
      fips: enabled
  template:
    metadata:
      labels:
        app: postgresql
        fips: enabled
    spec:
      # Node selection for FIPS-compatible hosts
      nodeSelector:
        kubernetes.io/arch: amd64
        kernel-version: "6.8"

      # Security context
      securityContext:
        fsGroup: 1001
        runAsUser: 1001
        runAsNonRoot: true

      containers:
      - name: postgresql
        image: postgresql-fips-ubuntu:17.6.0
        imagePullPolicy: IfNotPresent

        ports:
        - name: postgresql
          containerPort: 5432

        env:
        - name: POSTGRESQL_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgresql-secret
              key: postgresql-password
        - name: POSTGRESQL_DATABASE
          value: "production_db"
        - name: POSTGRESQL_REPLICATION_MODE
          value: "master"  # Set to "slave" for replicas
        - name: POSTGRESQL_REPLICATION_USER
          value: "repl_user"
        - name: POSTGRESQL_REPLICATION_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgresql-secret
              key: replication-password

        volumeMounts:
        - name: data
          mountPath: /bitnami/postgresql
        - name: config
          mountPath: /opt/bitnami/postgresql/conf/postgresql.conf
          subPath: postgresql.conf

        livenessProbe:
          exec:
            command:
            - /bin/sh
            - -c
            - pg_isready -U postgres
          initialDelaySeconds: 60
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3

        readinessProbe:
          exec:
            command:
            - /bin/sh
            - -c
            - pg_isready -U postgres
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3

        resources:
          requests:
            memory: "4Gi"
            cpu: "2000m"
          limits:
            memory: "8Gi"
            cpu: "4000m"

      volumes:
      - name: config
        configMap:
          name: postgresql-config

  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: "fast-ssd"
      resources:
        requests:
          storage: 100Gi
```

**5. Service:**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: postgresql
  namespace: postgresql-fips
spec:
  type: ClusterIP
  ports:
  - port: 5432
    targetPort: 5432
    protocol: TCP
    name: postgresql
  selector:
    app: postgresql
---
apiVersion: v1
kind: Service
metadata:
  name: postgresql-headless
  namespace: postgresql-fips
spec:
  type: ClusterIP
  clusterIP: None
  ports:
  - port: 5432
    targetPort: 5432
    protocol: TCP
    name: postgresql
  selector:
    app: postgresql
```

**6. NetworkPolicy (Optional, for strict isolation):**
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: postgresql-netpol
  namespace: postgresql-fips
spec:
  podSelector:
    matchLabels:
      app: postgresql
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          authorized: "true"
    ports:
    - protocol: TCP
      port: 5432
  egress:
  - to:
    - namespaceSelector: {}
    ports:
    - protocol: TCP
      port: 53  # DNS
```

**Deployment Commands:**
```bash
# Create namespace and resources
kubectl apply -f namespace.yaml
kubectl apply -f secret.yaml
kubectl apply -f configmap.yaml
kubectl apply -f statefulset.yaml
kubectl apply -f service.yaml

# Verify deployment
kubectl get pods -n postgresql-fips
kubectl logs -n postgresql-fips postgresql-0 | grep "FIPS VALIDATION"

# Test connection
kubectl run -it --rm psql-client --image=postgres:17-alpine --namespace=postgresql-fips -- \
  psql -h postgresql.postgresql-fips.svc.cluster.local -U postgres
```

**Characteristics:**
- ✅ Cloud-native deployment
- ✅ Automatic pod rescheduling
- ✅ Persistent storage
- ✅ Service discovery
- ✅ FIPS compliance per pod
- ✅ Horizontal scalability (read replicas)
- ✅ Production-grade
- ⚠️ Requires Kubernetes expertise
- ⚠️ Node selector ensures FIPS-compatible hosts

---

## 5. Network Architecture

### 5.1 Network Security Zones

**Recommended Zone Segmentation:**

```
┌─────────────────────────────────────────────────┐
│         Internet / Public Zone                  │
└──────────────────┬──────────────────────────────┘
                   │
         ┌─────────▼─────────┐
         │   Load Balancer   │
         │   (TLS Termination│
         │    with FIPS)     │
         └─────────┬─────────┘
                   │
┌──────────────────▼──────────────────────────────┐
│         DMZ / Application Zone                  │
│  ┌───────────────────────────────────────────┐  │
│  │     Application Servers                   │  │
│  │     (Can connect to PostgreSQL)           │  │
│  └───────────────────────────────────────────┘  │
└──────────────────┬──────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────┐
│         Database Zone (Restricted)              │
│  ┌───────────────────────────────────────────┐  │
│  │     PostgreSQL FIPS Cluster               │  │
│  │     (5432 - No external access)           │  │
│  └───────────────────────────────────────────┘  │
│                                                  │
│  Access:                                         │
│  - Application Zone: ✓ Allowed                  │
│  - DMZ: ✗ Blocked                                │
│  - Internet: ✗ Blocked                           │
└──────────────────────────────────────────────────┘
```

### 5.2 Firewall Rules

**Database Zone Ingress Rules:**
```bash
# Allow PostgreSQL from application zone
iptables -A INPUT -p tcp --dport 5432 -s 10.0.2.0/24 -j ACCEPT

# Allow replication between PostgreSQL nodes
iptables -A INPUT -p tcp --dport 5432 -s 10.0.3.0/24 -j ACCEPT

# Block all other access
iptables -A INPUT -p tcp --dport 5432 -j DROP
```

### 5.3 TLS/SSL Configuration

**Client Connection Security:**

All client connections should use SSL/TLS:

```bash
# Client connection string
postgresql://user:pass@host:5432/db?sslmode=require&sslrootcert=/path/to/ca.crt
```

**SSL Mode Options:**
- `require` - Minimum for production
- `verify-ca` - Verify server certificate
- `verify-full` - Verify server certificate and hostname

**FIPS-Approved Cipher Suites:**
```
TLS_AES_256_GCM_SHA384
TLS_AES_128_GCM_SHA256
TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384
TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256
```

---

## 6. Data Management

### 6.1 Storage Configuration

**Production Storage Layout:**

```
/data/
├── postgresql/          # PostgreSQL data directory
│   ├── data/           # Database files
│   ├── wal/            # Write-Ahead Logs (separate disk recommended)
│   └── pg_stat_tmp/    # Temporary statistics files
├── backup/              # Local backup staging
│   ├── base/           # Base backups
│   ├── wal_archive/    # Archived WAL files
│   └── exports/        # pg_dump exports
└── logs/                # Application logs
    ├── postgresql/     # PostgreSQL logs
    └── fips/           # FIPS validation logs
```

**Storage Classes:**
- **Data:** High-performance SSD/NVMe (lowest latency)
- **WAL:** Separate SSD (sequential writes)
- **Backup:** Standard SSD or HDD (cost-effective)

### 6.2 Backup Strategy

**3-2-1 Backup Rule:**
- **3** copies of data
- **2** different storage types
- **1** off-site copy

**Backup Types:**

1. **Continuous WAL Archiving**
   ```bash
   # Enable WAL archiving
   archive_mode = on
   archive_command = 'cp %p /backup/wal_archive/%f'
   ```

2. **Base Backups (Daily)**
   ```bash
   # pg_basebackup
   docker exec postgresql-fips \
     pg_basebackup -D /backup/base/$(date +%Y%m%d) \
     -Ft -z -P -U postgres
   ```

3. **Logical Backups (Weekly)**
   ```bash
   # pg_dump
   docker exec postgresql-fips \
     pg_dump -U postgres -Fc production_db > \
     /backup/exports/production_db_$(date +%Y%m%d).dump
   ```

**Backup Schedule:**
- Continuous: WAL archiving
- Daily: Base backup (retain 7 days)
- Weekly: Full dump (retain 4 weeks)
- Monthly: Full dump (retain 12 months)

**Off-site Backup:**
```bash
# Sync to S3 (FIPS-compliant endpoint)
aws s3 sync /backup/base/ \
  s3://backups/postgresql-fips/base/ \
  --sse AES256
```

### 6.3 Disaster Recovery

**Recovery Time Objective (RTO):** < 4 hours
**Recovery Point Objective (RPO):** < 15 minutes

**Recovery Procedures:**

1. **Point-in-Time Recovery (PITR)**
   ```bash
   # Restore base backup
   tar -xzf /backup/base/20251203.tar.gz -C /data/postgresql/

   # Configure recovery
   cat > /data/postgresql/recovery.conf <<EOF
   restore_command = 'cp /backup/wal_archive/%f %p'
   recovery_target_time = '2025-12-03 14:30:00'
   EOF

   # Start PostgreSQL
   docker start postgresql-fips
   ```

2. **Standby Promotion (HA Failover)**
   ```bash
   # Promote replica to primary
   docker exec postgresql-replica-1 \
     pg_ctl promote -D /bitnami/postgresql/data
   ```

---

## 7. Monitoring and Observability

### 7.1 Metrics to Monitor

**FIPS Compliance Metrics:**
- Container startup success rate
- FIPS validation pass/fail rate
- Non-FIPS library detection events
- Entropy availability

**PostgreSQL Metrics:**
- Connection count
- Transaction rate (commits/rollbacks)
- Query latency (p50, p95, p99)
- Cache hit ratio
- Replication lag (HA setups)
- Disk I/O and space usage

**System Metrics:**
- CPU utilization
- Memory usage
- Disk I/O (IOPS, throughput)
- Network I/O

### 7.2 Prometheus Monitoring

**postgres_exporter Configuration:**
```yaml
# docker-compose.yml addition
  postgres-exporter:
    image: quay.io/prometheuscommunity/postgres-exporter:latest
    ports:
      - "9187:9187"
    environment:
      - DATA_SOURCE_NAME=postgresql://postgres:password@postgresql:5432/postgres?sslmode=require
    depends_on:
      - postgresql
```

**Key Prometheus Queries:**
```promql
# Connection count
pg_stat_database_numbackends{datname="production_db"}

# Transaction rate
rate(pg_stat_database_xact_commit{datname="production_db"}[5m])

# Cache hit ratio
rate(pg_stat_database_blks_hit[5m]) /
(rate(pg_stat_database_blks_hit[5m]) + rate(pg_stat_database_blks_read[5m]))

# Replication lag
pg_replication_lag_seconds
```

### 7.3 Logging

**Log Aggregation:**
- Centralized logging via ELK, Splunk, or CloudWatch
- FIPS validation logs retained for audit
- PostgreSQL query logs (configurable verbosity)

**Log Retention:**
- Operational logs: 30 days
- Security/audit logs: 1 year minimum (FedRAMP requirement)
- FIPS validation logs: Permanent

---

## 8. Security Controls

### 8.1 Access Control

**Database Users:**
- **Superuser (postgres):** Break-glass only, MFA required
- **Application Users:** Least privilege, connection limits
- **Replication User:** Replication-only privileges
- **Monitoring User:** Read-only statistics access

**Example User Creation:**
```sql
-- Application user
CREATE ROLE app_user LOGIN PASSWORD 'secure_password' CONNECTION LIMIT 50;
GRANT CONNECT ON DATABASE production_db TO app_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_user;

-- Read-only monitoring user
CREATE ROLE monitor LOGIN PASSWORD 'monitor_password' CONNECTION LIMIT 5;
GRANT pg_monitor TO monitor;
```

### 8.2 Network Isolation

**Container Network:**
```bash
# Create isolated network
docker network create \
  --driver bridge \
  --subnet 172.20.0.0/16 \
  --opt com.docker.network.bridge.name=br-pg-fips \
  postgresql-fips-net

# Run container on isolated network
docker run -d \
  --network postgresql-fips-net \
  --name postgresql-fips \
  postgresql-fips-ubuntu:17.6.0
```

### 8.3 Secrets Management

**Recommended Solutions:**
- HashiCorp Vault
- AWS Secrets Manager
- Azure Key Vault
- Kubernetes Secrets (with encryption at rest)

**Example with Vault:**
```bash
# Store secret in Vault
vault kv put secret/postgresql/production \
  password="SecurePassword123!"

# Retrieve in container
export POSTGRESQL_PASSWORD=$(vault kv get -field=password secret/postgresql/production)
```

---

## 9. Operational Procedures

### 9.1 Deployment Checklist

**Pre-Deployment:**
- [ ] Host kernel >= 6.8.x verified
- [ ] Host architecture is x86_64
- [ ] RDRAND available (check /proc/cpuinfo)
- [ ] Storage provisioned and mounted
- [ ] Network configuration completed
- [ ] Secrets configured
- [ ] Backup solution in place
- [ ] Monitoring configured

**During Deployment:**
- [ ] Container starts successfully
- [ ] FIPS validation passes (check logs)
- [ ] Database initializes
- [ ] Connectivity test passes
- [ ] SSL/TLS enabled and working
- [ ] Replication configured (if HA)

**Post-Deployment:**
- [ ] Backup test successful
- [ ] Monitoring dashboards show data
- [ ] Alerting rules configured
- [ ] Documentation updated
- [ ] Runbook created

### 9.2 Upgrade Procedures

**Rolling Upgrade (Zero Downtime):**

1. **Upgrade replica 1:**
   ```bash
   docker stop postgresql-replica-1
   docker rm postgresql-replica-1
   docker run -d --name postgresql-replica-1 \
     [same config with new image version]
   # Wait for catch-up
   ```

2. **Upgrade replica 2:**
   (Repeat step 1)

3. **Failover to replica:**
   ```bash
   # Promote replica-1 to primary
   docker exec postgresql-replica-1 pg_ctl promote
   ```

4. **Upgrade old primary:**
   ```bash
   docker stop postgresql-primary
   # Reconfigure as replica with new image
   ```

5. **Failover back (optional)**

### 9.3 Incident Response

**FIPS Validation Failure:**
1. Container won't start, logs show FIPS failure
2. Check:
   - Host kernel version
   - CPU architecture
   - Entropy availability
   - System OpenSSL presence (should be absent)
3. Review `docs/verification-guide.md` for troubleshooting
4. Escalate to security team if crypto module compromised

**Performance Degradation:**
1. Check monitoring dashboards
2. Investigate slow queries (pg_stat_statements)
3. Review connection count
4. Check disk I/O and space
5. Scale horizontally (add read replicas) if needed

---

## 10. Compliance Maintenance

### 10.1 Continuous Compliance

**Monthly Tasks:**
- Review FIPS validation logs
- Update security patches
- Test backups and recovery
- Review access logs

**Quarterly Tasks:**
- Full disaster recovery test
- Security assessment
- Compliance documentation review
- Update OE mapping if kernel changes

**Annually:**
- Re-run full verification suite
- Update wolfSSL CMVP certificate (if renewed)
- Compliance audit preparation
- Training for operations team

### 10.2 Audit Readiness

**Evidence Collection:**
- FIPS validation logs (daily)
- Backup success logs
- Access audit logs
- Change management records
- Incident response records

**3PAO Review Package:**
- Architecture diagrams (this document)
- Network diagrams
- Data flow diagrams
- Security controls documentation
- Verification test results
- CMVP certificate and OE mapping

---

## 11. Cost Optimization

### 11.1 Resource Right-Sizing

**Development/Test:**
- Smaller instances (2 CPU, 4 GB RAM)
- Standard SSD storage
- No high availability

**Production:**
- Right-sized based on workload profiling
- Use auto-scaling for read replicas
- Reserved/committed use discounts

### 11.2 Storage Optimization

- Compress backups
- Use lifecycle policies (move to cold storage after 90 days)
- Vacuum and analyze database regularly
- Archive old data to cheaper storage

---

## 12. Migration Strategies

### 12.1 Migrating from Non-FIPS PostgreSQL

**Approach:** Blue-Green Deployment

1. **Prepare:** Set up FIPS environment (green)
2. **Sync:** Replicate from existing (blue) to new (green)
3. **Test:** Validate FIPS environment works
4. **Switch:** Update DNS/load balancer to green
5. **Monitor:** Watch for issues
6. **Decommission:** Shut down blue after stability period

**pg_logical Replication:**
```sql
-- On existing (blue) PostgreSQL
CREATE PUBLICATION blue_pub FOR ALL TABLES;

-- On FIPS (green) PostgreSQL
CREATE SUBSCRIPTION green_sub
  CONNECTION 'host=blue-db port=5432 dbname=mydb'
  PUBLICATION blue_pub;
```

---

## Appendices

### Appendix A: Quick Reference

**Environment Variables:**
```bash
POSTGRESQL_PASSWORD        # Admin password
POSTGRESQL_DATABASE        # Initial database
POSTGRESQL_USERNAME        # Custom admin user
POSTGRESQL_MAX_CONNECTIONS # Max connections (default: 100)
POSTGRESQL_REPLICATION_MODE # master/slave
OPENSSL_CONF               # OpenSSL config (set by image)
```

### Appendix B: Useful Commands

```bash
# Check FIPS validation
docker logs <container> | grep "FIPS VALIDATION"

# Connect to database
docker exec -it <container> psql -U postgres

# View replication status
docker exec <container> psql -U postgres -c "SELECT * FROM pg_stat_replication;"

# Check PostgreSQL version
docker exec <container> postgres --version

# Backup database
docker exec <container> pg_dump -U postgres mydb > backup.sql

# Restore database
docker exec -i <container> psql -U postgres mydb < backup.sql
```

---

**Document Status:** Complete - Ready for Production Deployment

**Version History:**
| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-12-03 | Initial reference architecture |

**Next Review:** Upon major version update or infrastructure change

**Owner:** Root FIPS Implementation Team

**Classification:** Internal - Architecture Guide
