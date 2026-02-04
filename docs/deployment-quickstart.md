# PostgreSQL FIPS Container - Quick Start Deployment Guide

**Image:** postgresql-fips-ubuntu:17.6.0
**User:** Non-root (UID 1001)
**Base:** Ubuntu 22.04 LTS with wolfSSL FIPS v5

---

## Prerequisites

- Docker Engine 20.10+ with BuildKit
- Host running Linux kernel >= 6.8.x (for FIPS OE compliance)
- x86_64 architecture with RDRAND support (recommended)

---

## Quick Start

### 1. Prepare Data Directory

The container runs as non-root user (UID 1001) for security. You must set correct permissions on the host volume:

```bash
# Create data directory
sudo mkdir -p /data/postgresql

# Set ownership to UID 1001 (container user)
sudo chown -R 1001:1001 /data/postgresql

# Set secure permissions
sudo chmod 700 /data/postgresql

# Verify permissions
ls -la /data/postgresql
# Should show: drwx------ 2 1001 1001
```

### 2. Run Container

```bash
docker run \
  --name postgresql-fips \
  --restart=unless-stopped \
  -p 5432:5432 \
  -e POSTGRESQL_PASSWORD=secure_password \
  -e POSTGRESQL_DATABASE=appdb \
  -v /data/postgresql:/bitnami/postgresql \
  postgresql-fips-ubuntu:17.6.0
```

### 3. Verify FIPS Validation

The container performs 6 FIPS validation checks on startup:

```bash
docker logs postgresql-fips 2>&1 | grep -A 50 "FIPS Validation"
```

**Expected Output:**
```
================================================================================
                          FIPS Validation Starting
================================================================================

[1/6] Validating Operating Environment (OE) for CMVP compliance...
      Detected kernel: 6.8.x
      ✓ Kernel version: 6.8.x (validated range)
      ✓ CPU architecture: x86_64
      ✓ RDRAND: Available (hardware entropy source)

[2/6] Running wolfSSL FIPS startup checks...
      ✓ FIPS mode: Enabled
      ✓ Power-On Self Tests (POST): PASSED
      ✓ Known Answer Tests (KAT): PASSED
      ✓ RNG initialization: PASSED

[3/6] Verifying OpenSSL configuration...
      ✓ OpenSSL version: 3.0.15
      ✓ wolfProvider loaded and active

[4/6] Validating wolfSSL FIPS module integrity...
      ✓ wolfSSL FIPS v5 module verified

[5/6] Verifying PostgreSQL crypto linkage...
      ✓ PostgreSQL linked to FIPS OpenSSL

[6/6] Verifying no non-FIPS crypto libraries present...
      ✓ No system OpenSSL libraries found

================================================================================
                     ✓ FIPS Validation: PASSED
================================================================================
```

---

## Alternative Deployment Methods

### Method 1: Using Docker Volume (Recommended for Production)

Docker manages volume permissions automatically:

```bash
# Create named volume
docker volume create postgresql-fips-data

# Run container
docker run \
  --name postgresql-fips \
  --restart=unless-stopped \
  -p 5432:5432 \
  -e POSTGRESQL_PASSWORD=secure_password \
  -e POSTGRESQL_DATABASE=appdb \
  -v postgresql-fips-data:/bitnami/postgresql \
  postgresql-fips-ubuntu:17.6.0
```

### Method 2: Using Docker Compose

Create `docker-compose.yml`:

```yaml
version: '3.8'

services:
  postgresql-fips:
    image: postgresql-fips-ubuntu:17.6.0
    container_name: postgresql-fips
    restart: unless-stopped
    ports:
      - "5432:5432"
    environment:
      - POSTGRESQL_PASSWORD=secure_password
      - POSTGRESQL_DATABASE=appdb
      - POSTGRESQL_USERNAME=postgres
    volumes:
      - postgresql-fips-data:/bitnami/postgresql
    # Optional: Resource limits
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 2G
        reservations:
          cpus: '1'
          memory: 1G

volumes:
  postgresql-fips-data:
    driver: local
```

Start with:
```bash
docker-compose up -d
```

### Method 3: Kubernetes Deployment

See `docs/reference-architecture.md` for complete Kubernetes deployment examples.

---

## Environment Variables

### Required

| Variable | Description | Example |
|----------|-------------|---------|
| `POSTGRESQL_PASSWORD` | PostgreSQL password | `secure_password` |

### Optional

| Variable | Description | Default |
|----------|-------------|---------|
| `POSTGRESQL_USERNAME` | PostgreSQL username | `postgres` |
| `POSTGRESQL_DATABASE` | Database to create | `postgres` |
| `POSTGRESQL_PORT_NUMBER` | PostgreSQL port | `5432` |
| `POSTGRESQL_INITDB_ARGS` | Additional initdb args | `--encoding=UTF8 --lc-collate=C --lc-ctype=C` |

### FIPS-Specific

| Variable | Description | Default |
|----------|-------------|---------|
| `OPENSSL_CONF` | OpenSSL config path | `/usr/local/openssl/ssl/openssl.cnf` |
| `OPENSSL_MODULES` | OpenSSL modules path | `/usr/local/lib64/ossl-modules` |
| `LD_LIBRARY_PATH` | Library path | `/usr/local/openssl/lib64:/usr/local/lib` |

---

## Connecting to PostgreSQL

### Using psql (from host)

```bash
# Install PostgreSQL client if needed
sudo apt-get install postgresql-client

# Connect
psql -h localhost -p 5432 -U postgres -d appdb
```

### Using psql (from container)

```bash
docker exec -it postgresql-fips psql -U postgres -d appdb
```

### Connection String

```
postgresql://postgres:secure_password@localhost:5432/appdb?sslmode=require
```

---

## Verification Commands

### Check Container Status

```bash
# Container running
docker ps | grep postgresql-fips

# View logs
docker logs postgresql-fips

# Container resource usage
docker stats postgresql-fips
```

### Verify FIPS Mode

```bash
# Check OpenSSL FIPS mode
docker exec postgresql-fips openssl list -providers

# Expected output should include:
#   default
#     name: OpenSSL Default Provider
#     version: 3.0.15
#     status: active
#   wolfprovider
#     name: wolfSSL Provider
#     version: 1.1.0
#     status: active
```

### Test Database Connection

```bash
# Simple connection test
docker exec postgresql-fips psql -U postgres -c "SELECT version();"

# Test pgcrypto (should use FIPS crypto)
docker exec postgresql-fips psql -U postgres -c "
  CREATE EXTENSION IF NOT EXISTS pgcrypto;
  SELECT encode(digest('test', 'sha256'), 'hex');
"
```

### Verify Crypto Path

```bash
# Check PostgreSQL binary linkage
docker exec postgresql-fips ldd /opt/bitnami/postgresql/bin/postgres | grep ssl

# Should show FIPS OpenSSL:
#   libssl.so.3 => /usr/local/openssl/lib64/libssl.so.3
#   libcrypto.so.3 => /usr/local/openssl/lib64/libcrypto.so.3
```

---

## Troubleshooting

### Permission Denied Error

**Error:**
```
mkdir: cannot create directory '/bitnami/postgresql/data': Permission denied
```

**Solution:**
```bash
sudo chown -R 1001:1001 /data/postgresql
sudo chmod 700 /data/postgresql
```

### FIPS Validation Failed

**Error:**
```
✗ FIPS VALIDATION FAILED
```

**Check:**
1. Kernel version: `uname -r` (must be >= 6.8.x)
2. CPU architecture: `uname -m` (must be x86_64)
3. Container logs: `docker logs postgresql-fips`

### Port Already in Use

**Error:**
```
Error starting userland proxy: listen tcp4 0.0.0.0:5432: bind: address already in use
```

**Solution:**
```bash
# Find process using port 5432
sudo lsof -i :5432

# Stop existing PostgreSQL or use different port
docker run -p 5433:5432 ...
```

### Container Exits Immediately

**Check logs:**
```bash
docker logs postgresql-fips
```

**Common causes:**
1. FIPS validation failed (check OE requirements)
2. Invalid environment variables
3. Volume permission issues

---

## Security Considerations

### Non-Root User

The container runs as UID 1001 (non-root) for security:
- Reduced attack surface
- Principle of least privilege
- Compliant with FedRAMP requirements

### Network Security

**Recommended:**
- Use internal Docker network (not host network)
- Enable SSL/TLS for PostgreSQL connections
- Use strong passwords (minimum 16 characters)
- Implement network segmentation

**Example with custom network:**
```bash
# Create network
docker network create --driver bridge postgresql-net

# Run container
docker run \
  --name postgresql-fips \
  --network postgresql-net \
  -e POSTGRESQL_PASSWORD=secure_password \
  -v /data/postgresql:/bitnami/postgresql \
  postgresql-fips-ubuntu:17.6.0
```

### Data at Rest Encryption

Consider using encrypted volumes:

```bash
# Create encrypted volume (example using LUKS)
sudo cryptsetup luksFormat /dev/sdb1
sudo cryptsetup open /dev/sdb1 postgresql-encrypted
sudo mkfs.ext4 /dev/mapper/postgresql-encrypted
sudo mount /dev/mapper/postgresql-encrypted /data/postgresql
sudo chown -R 1001:1001 /data/postgresql
```

---

## Performance Tuning

### PostgreSQL Configuration

Mount custom `postgresql.conf`:

```bash
docker run \
  --name postgresql-fips \
  -v /data/postgresql:/bitnami/postgresql \
  -v /path/to/postgresql.conf:/opt/bitnami/postgresql/conf/postgresql.conf:ro \
  postgresql-fips-ubuntu:17.6.0
```

### Resource Limits

```bash
docker run \
  --name postgresql-fips \
  --cpus="2" \
  --memory="2g" \
  --memory-swap="2g" \
  -v /data/postgresql:/bitnami/postgresql \
  postgresql-fips-ubuntu:17.6.0
```

---

## Backup and Recovery

### Backup

```bash
# Create backup
docker exec postgresql-fips pg_dump -U postgres appdb > backup.sql

# Or using pg_dumpall
docker exec postgresql-fips pg_dumpall -U postgres > backup_all.sql
```

### Restore

```bash
# Restore database
docker exec -i postgresql-fips psql -U postgres appdb < backup.sql
```

### Volume Backup

```bash
# Stop container
docker stop postgresql-fips

# Backup volume
sudo tar czf postgresql-backup-$(date +%Y%m%d).tar.gz -C /data postgresql

# Start container
docker start postgresql-fips
```

---

## Next Steps

- Review [Reference Architecture](reference-architecture.md) for production deployments
- See [Verification Guide](verification-guide.md) for compliance testing
- Check [Build Documentation](build-documentation.md) for customization

---

## Support and Issues

For issues or questions:
1. Check container logs: `docker logs postgresql-fips`
2. Verify FIPS validation: See section "Verify FIPS Validation" above
3. Review troubleshooting section
4. Consult documentation in `docs/` directory
