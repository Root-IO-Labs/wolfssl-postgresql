# FIPS-Enabled Ubuntu PostgreSQL Docker Image

A FIPS 140-3 compliant PostgreSQL 17.7 Docker image built on **Ubuntu 22.04** with Bitnami scripts, providing cryptographic validation through wolfSSL FIPS v5 and wolfProvider.

## Quick Overview

- **Base OS:** Ubuntu 22.04 LTS
- **PostgreSQL:** 17.7 (built from source)
- **FIPS Module:** wolfSSL FIPS v5 (FIPS 140-3 validated)
- **Compatibility:** Bitnami scripts and directory structure
- **User ID:** 1001 (Bitnami standard)
- **Build Variants:** Standard (FIPS only) and Hardened (FIPS + STIG/CIS)

## Build Variants

Two Dockerfiles are available:

- **Dockerfile** - FIPS 140-3 compliant image
- **Dockerfile.hardened** - FIPS 140-3 + DISA STIG/CIS hardened image

## Key Features

- ✅ **FIPS 140-3 Compliant** - wolfSSL FIPS v5 validated cryptography
- ✅ **Ubuntu 22.04 Base** - Latest Ubuntu LTS
- ✅ **Bitnami Compatible** - Uses original Bitnami scripts
- ✅ **Multi-Stage Build** - Optimized 3-stage build process
- ✅ **Comprehensive Validation** - 5-stage FIPS validation on startup
- ✅ **Production Ready** - Security hardened, fully documented

## Architecture

### Multi-Stage Build

```
Stage 1: builder (Ubuntu 22.04)
├── OpenSSL 3.0.15 with FIPS support
├── wolfSSL FIPS v5 (commercial package)
├── wolfProvider (OpenSSL 3 provider)
└── FIPS validation utilities

Stage 2: postgres-builder
├── Inherits crypto stack from Stage 1
└── Build PostgreSQL 17.7 with custom OpenSSL

Stage 3: runtime (Ubuntu 22.04)
├── Copy binaries from previous stages
├── Install runtime dependencies
├── Copy Bitnami scripts (rootfs/)
└── Configure FIPS environment
```

### FIPS Cryptography Stack

```
PostgreSQL Application
        ↓
OpenSSL 3 API (libssl/libcrypto)
        ↓
wolfProvider (OpenSSL 3 Provider)
        ↓
wolfSSL FIPS v5 (Validated Module)
        ↓
FIPS 140-3 Compliant Operations
```

## Prerequisites

- Docker 20.10+ with BuildKit support
- Docker Buildx plugin
- wolfSSL FIPS package password (commercial license)
- 4GB+ RAM for build
- 10GB+ disk space

### Required Files

**Standard Build (Dockerfile):**
- Dockerfile
- wolfssl_password.txt
- fips-entrypoint.sh
- openssl-wolfprov.cnf
- test-fips.c
- fips-startup-check.c
- rootfs/ directory
- prebuildfs/ directory

**Hardened Build (Dockerfile.hardened):**
- All files from standard build
- Dockerfile.hardened
- build-hardened.sh
- patches/ directory (CVE patches)

## Common Tasks Quick Reference

### Running Tests with Password

```bash
# The test script requires PGPASSWORD for PostgreSQL crypto tests (Test 5/6)
docker exec -e PGPASSWORD=YourPassword postgresql-fips-ubuntu /usr/local/bin/test-provider.sh
```

### Connecting to PostgreSQL

```bash
# With password (recommended)
docker exec -e PGPASSWORD=YourPassword postgresql-fips-ubuntu psql -U postgres

# From host machine
PGPASSWORD=YourPassword psql -h localhost -p 5432 -U postgres
```

### Important Environment Variables

- **POSTGRESQL_PASSWORD**: Sets database password at container startup
- **PGPASSWORD**: Authenticates `psql` client connections (must match POSTGRESQL_PASSWORD)
- Use `-e PGPASSWORD=<password>` with `docker exec` to run tests or connect to database

💡 **Remember:** Both passwords should match! Example: If `POSTGRESQL_PASSWORD=SecurePass123`, then use `PGPASSWORD=SecurePass123`.

---

## Quick Start

### 1. Prepare wolfSSL Password

```bash
echo 'your-wolfssl-password' > wolfssl_password.txt
chmod 600 wolfssl_password.txt
```

### 2. Build the Image

**Standard Build (FIPS Only):**

```bash
# Using build script (recommended)
./build.sh

# Or manually
DOCKER_BUILDKIT=1 docker buildx build \
  --secret id=wolfssl_password,src=wolfssl_password.txt \
  -t postgresql-fips-ubuntu:17.7.0 .
```

**Hardened Build (FIPS + STIG/CIS):**

```bash
# Using build script (recommended)
./build-hardened.sh

# Or manually
DOCKER_BUILDKIT=1 docker buildx build \
  --secret id=wolfssl_password,src=wolfssl_password.txt \
  -t postgresql-fips-ubuntu:17.7.0-hardened \
  -f Dockerfile.hardened .
```

**Build time:** 25-35 minutes (first build), 2-5 minutes (cached)

### 3. Run the Container

```bash
# Using docker-compose (recommended)
docker-compose up -d

# Or using docker run
docker run -d \
  --name postgresql-fips \
  -e POSTGRESQL_PASSWORD=SecurePass123 \
  -p 5432:5432 \
  -v postgresql_data:/bitnami/postgresql \
  postgresql-fips-ubuntu:17.7.0
```

### 4. Verify FIPS Compliance

**Note:** Container name depends on how you started it:
- With `docker-compose`: Use `postgresql-fips-ubuntu`
- With `docker run --name postgresql-fips`: Use `postgresql-fips`
- Check actual name: `docker ps --format '{{.Names}}' | grep postgres`

```bash
# View startup validation
# For docker-compose:
docker logs postgresql-fips-ubuntu | grep FIPS
# For docker run:
docker logs postgresql-fips | grep FIPS

# Run provider test (Note: Some tests require PostgreSQL password)
# For docker-compose:
docker exec postgresql-fips-ubuntu /usr/local/bin/test-provider.sh
# For docker run:
docker exec postgresql-fips /usr/local/bin/test-provider.sh

# Check OpenSSL providers
# For docker-compose:
docker exec postgresql-fips-ubuntu openssl list -providers
# For docker run:
docker exec postgresql-fips openssl list -providers

# Test PostgreSQL cryptographic functions (with password)
# For docker-compose:
docker exec postgresql-fips-ubuntu bash -c \
  'PGPASSWORD=SecurePass123 psql -U postgres -c "CREATE EXTENSION IF NOT EXISTS pgcrypto;"'
# For docker run:
docker exec postgresql-fips bash -c \
  'PGPASSWORD=SecurePass123 psql -U postgres -c "CREATE EXTENSION IF NOT EXISTS pgcrypto;"'

# Test cryptographic digest
# For docker-compose:
docker exec postgresql-fips-ubuntu bash -c \
  'PGPASSWORD=SecurePass123 psql -U postgres -c "SELECT encode(digest('\''test'\'', '\''sha256'\''), '\''hex'\'');"'
# For docker run:
docker exec postgresql-fips bash -c \
  'PGPASSWORD=SecurePass123 psql -U postgres -c "SELECT encode(digest('\''test'\'', '\''sha256'\''), '\''hex'\'');"'
```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `POSTGRESQL_USERNAME` | `postgres` | PostgreSQL superuser name |
| `POSTGRESQL_PASSWORD` | - | PostgreSQL password (required) |
| `POSTGRESQL_DATABASE` | `postgres` | Default database to create |
| `POSTGRESQL_PORT_NUMBER` | `5432` | PostgreSQL port |
| `SKIP_FIPS_CHECK` | `false` | Skip FIPS validation (not recommended) |
| `BITNAMI_APP_NAME` | `postgresql-fips` | Bitnami app identifier |
| `PGPASSWORD` | - | Used for testing and client connections (set via `-e` flag with docker exec) |

**Understanding POSTGRESQL_PASSWORD vs PGPASSWORD:**

These are two different environment variables with different purposes:

| Variable | Purpose | When to Set | How to Set |
|----------|---------|-------------|------------|
| `POSTGRESQL_PASSWORD` | Sets the PostgreSQL user password during initialization | Container startup | `-e POSTGRESQL_PASSWORD=...` in `docker run` or in `docker-compose.yml` |
| `PGPASSWORD` | Provides password for `psql` client authentication | When running `psql` commands or tests | `-e PGPASSWORD=...` with `docker exec` |

**Key Points:**
- ✅ `POSTGRESQL_PASSWORD` configures the database password (set once at startup)
- ✅ `PGPASSWORD` authenticates client connections (set each time you run `psql`)
- ✅ Both should have the **same value** for successful authentication
- ✅ `PGPASSWORD` is NOT persisted in the container - it's passed per command

**Examples:**

```bash
# 1. Start container with POSTGRESQL_PASSWORD
docker run -d --name postgresql-fips \
  -e POSTGRESQL_PASSWORD=SecurePass123 \
  postgresql-fips-ubuntu:17.7.0

# 2. Connect to PostgreSQL using PGPASSWORD (must match the password above)
docker exec -e PGPASSWORD=SecurePass123 postgresql-fips psql -U postgres

# 3. Run FIPS tests with PGPASSWORD
docker exec -e PGPASSWORD=SecurePass123 postgresql-fips /usr/local/bin/test-provider.sh
```

### FIPS Environment (Automatic)

These are set automatically:

- `OPENSSL_CONF=/usr/local/openssl/ssl/openssl.cnf`
- `OPENSSL_MODULES=/usr/local/lib64/ossl-modules`
- `LD_LIBRARY_PATH=/usr/local/openssl/lib64:/usr/local/lib`

## FIPS Validation

### Startup Validation Process

The container performs comprehensive FIPS validation:

1. **Environment Validation** - Checks OPENSSL_CONF, OPENSSL_MODULES, LD_LIBRARY_PATH
2. **OpenSSL Validation** - Verifies OpenSSL 3.x installation
3. **wolfSSL Validation** - Confirms wolfSSL library presence
4. **wolfProvider Validation** - Checks provider module
5. **Cryptographic Validation** - Runs FIPS Known Answer Tests (CAST)

### Validation Output Example

```
========================================
PostgreSQL FIPS Container Startup
Ubuntu 22.04 + Bitnami Scripts
========================================

[1/5] Validating FIPS environment variables...
      ✓ OPENSSL_CONF: /usr/local/openssl/ssl/openssl.cnf
      ✓ OPENSSL_MODULES: /usr/local/lib64/ossl-modules
      ✓ LD_LIBRARY_PATH: /usr/local/openssl/lib64:/usr/local/lib

[2/5] Validating OpenSSL installation...
      ✓ OpenSSL found: OpenSSL 3.0.15

[3/5] Validating wolfSSL library...
      ✓ wolfSSL library: /usr/local/lib/libwolfssl.so

[4/5] Validating wolfProvider module...
      ✓ wolfProvider module: /usr/local/lib64/ossl-modules/libwolfprov.so

[5/5] Running cryptographic FIPS validation...
      ✓ FIPS mode: ENABLED
      ✓ FIPS version: 5
      ✓ FIPS CAST: PASSED

========================================
✓ ALL FIPS CHECKS PASSED
========================================

Handing control to Bitnami entrypoint...
```

## Bitnami Compatibility

This image maintains full compatibility with Bitnami PostgreSQL:

### Directory Structure

```
/opt/bitnami/postgresql/    # PostgreSQL installation
/bitnami/postgresql/data/   # Data directory (PGDATA)
/docker-entrypoint-initdb.d/   # Initialization scripts
/docker-entrypoint-preinitdb.d/  # Pre-initialization scripts
```

### Bitnami Scripts

All original Bitnami scripts are preserved:

- `/opt/bitnami/scripts/postgresql/entrypoint.sh` - Main entrypoint
- `/opt/bitnami/scripts/postgresql/setup.sh` - Database setup
- `/opt/bitnami/scripts/postgresql/run.sh` - PostgreSQL run script
- `/opt/bitnami/scripts/libpostgresql.sh` - PostgreSQL functions

### User/Group

- User: UID 1001 (Bitnami standard)
- Group: GID 1001
- Home: /opt/bitnami/postgresql

## Usage Examples

### Basic Connection

```bash
# From host
psql -h localhost -p 5432 -U postgres

# From container (adjust name based on how you started it)
docker exec -it postgresql-fips-ubuntu psql -U postgres  # docker-compose
docker exec -it postgresql-fips psql -U postgres  # docker run

# From another container
docker run --rm --network=host postgresql:17 \
  psql -h localhost -p 5432 -U postgres
```

### Initialization Scripts

Place scripts in `init-scripts/` directory:

```bash
init-scripts/
├── 01-create-schema.sql
├── 02-seed-data.sql
└── 03-setup-extensions.sh
```

Mount to container:

```yaml
volumes:
  - ./init-scripts:/docker-entrypoint-initdb.d:ro
```

### Using docker-compose

```bash
# Start PostgreSQL
docker-compose up -d

# Start with pgAdmin
docker-compose --profile admin up -d

# View logs
docker-compose logs -f postgresql-fips

# Stop services
docker-compose down
```

## Testing

### FIPS Validation Test

The test-provider.sh script runs a comprehensive 6-stage test of your FIPS setup. **Test 5 requires password authentication.**

```bash
# Full provider test suite (all 6 tests)
# IMPORTANT: Use -e PGPASSWORD matching your POSTGRESQL_PASSWORD value
# Adjust container name based on how you started it (postgresql-fips-ubuntu for docker-compose, postgresql-fips for docker run)

# Recommended: Run with password to test all 6 stages
docker exec -e PGPASSWORD=SecurePassword123! postgresql-fips-ubuntu /usr/local/bin/test-provider.sh  # docker-compose
docker exec -e PGPASSWORD=SecurePassword123! postgresql-fips /usr/local/bin/test-provider.sh  # docker run

# Alternative: Without password (Tests 1-4,6 will pass, Test 5 will be skipped gracefully)
docker exec postgresql-fips-ubuntu /usr/local/bin/test-provider.sh  # docker-compose
docker exec postgresql-fips /usr/local/bin/test-provider.sh  # docker run

# Check providers
docker exec postgresql-fips-ubuntu openssl list -providers  # docker-compose
docker exec postgresql-fips openssl list -providers  # docker run

# Test cryptographic operations at OpenSSL level
docker exec postgresql-fips-ubuntu openssl rand -hex 32  # docker-compose
docker exec postgresql-fips openssl rand -hex 32  # docker run

docker exec postgresql-fips-ubuntu openssl dgst -sha256 /etc/hostname  # docker-compose
docker exec postgresql-fips openssl dgst -sha256 /etc/hostname  # docker run

# Test PostgreSQL cryptographic functions (complete test) - using docker-compose name
docker exec postgresql-fips-ubuntu bash -c '
PGPASSWORD=${POSTGRESQL_PASSWORD:-SecurePass123} psql -U postgres << EOF
-- Install pgcrypto extension
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Test FIPS-compliant operations
SELECT '\''PostgreSQL FIPS Crypto Test'\'' AS test;
SELECT encode(digest('\''test data'\'', '\''sha256'\''), '\''hex'\'') AS sha256;
SELECT encode(digest('\''test data'\'', '\''sha512'\''), '\''hex'\'') AS sha512;
SELECT encode(encrypt('\''secret'\'', '\''key'\'', '\''aes'\''), '\''hex'\'') AS aes;
SELECT encode(gen_random_bytes(16), '\''hex'\'') AS random;
SELECT gen_random_uuid() AS uuid;
EOF
'
```

### Expected Test Results

When running the provider test suite, you may see these expected behaviors:

**Important: Password Requirement for Test 5**

Test 5 (PostgreSQL cryptographic functions) **requires authentication**. If you run the test script without providing `PGPASSWORD`, Test 5 will be automatically skipped with a helpful message. To run all tests including PostgreSQL crypto tests:

```bash
# Use -e PGPASSWORD with the value matching POSTGRESQL_PASSWORD
docker exec -e PGPASSWORD=SecurePassword123! postgresql-fips-ubuntu /usr/local/bin/test-provider.sh
```

**Expected Warnings in Test 3 (OpenSSL CLI Tests):**

When testing AES-256-CBC encryption/decryption, you'll see warnings about deprecated key derivation:
- `*** WARNING : deprecated key derivation used. Using -iter or -pbkdf2 would be better.`
- `error:030000E1:digital envelope routines:evp_md_from_algorithm:cache constants failed`

These warnings appear because:
1. wolfProvider v1.1.0 has limited support for PBKDF2-based key derivation
2. OpenSSL CLI tool uses password-based encryption by default
3. **However, the actual AES encryption/decryption still succeeds** (you'll see "✓ Encryption successful" and "✓ Decryption successful")
4. **PostgreSQL does NOT use PBKDF2** - it uses direct AES encryption, which works perfectly without any warnings

**Expected Behaviors:**

✅ **Test 1**: OpenSSL 3.0.15 configuration - Always passes
✅ **Test 2**: wolfProvider loaded and active - Always passes
✅ **Test 3**: OpenSSL CLI crypto operations
  - SHA-256: ✅ Works perfectly
  - AES-256-CBC: ✅ Works (with key derivation warnings - safe to ignore)
✅ **Test 4**: PostgreSQL 17.7 version check - Always passes
✅ **Test 5**: PostgreSQL cryptographic functions (with password)
  - pgcrypto extension: ✅ Installs successfully
  - MD5: ✅ Correctly blocked ("unsupported" error - expected in FIPS mode)
  - SHA-256: ✅ Works perfectly
  - SHA-512: ✅ Works perfectly
  - AES encryption: ✅ Works perfectly (no warnings!)
✅ **Test 6**: Library dependencies - Always passes

**Test Results Summary (With Password):**
```
========================================
✓ ALL TESTS PASSED
========================================

PostgreSQL is correctly configured with:
  - OpenSSL 3.0.15
  - wolfSSL FIPS v5.2.3
  - wolfProvider v1.1.0

All cryptographic operations are using
FIPS 140-3 validated algorithms.
```

**Key Findings:**
- ✅ All FIPS-approved algorithms (SHA-256, SHA-512, AES-256) work perfectly in PostgreSQL
- ✅ MD5 is correctly blocked, confirming FIPS compliance
- ✅ PostgreSQL cryptographic operations have NO warnings (unlike OpenSSL CLI)
- ⚠️ PBKDF2 key derivation warnings only affect OpenSSL CLI tool, not PostgreSQL
- ✅ Direct AES encryption (as used by PostgreSQL pgcrypto) is fully FIPS-compliant
- 🔐 Password authentication is required for PostgreSQL crypto tests (use `-e PGPASSWORD=<password>`)

### PostgreSQL Connectivity Test

```bash
# Check if PostgreSQL is ready (adjust container name)
docker exec postgresql-fips-ubuntu pg_isready -U postgres  # docker-compose
docker exec postgresql-fips pg_isready -U postgres  # docker run

# Run a simple query
docker exec postgresql-fips-ubuntu psql -U postgres -c "SELECT version();"  # docker-compose
docker exec postgresql-fips psql -U postgres -c "SELECT version();"  # docker run
```

## Troubleshooting

### Build Issues

**Problem:** wolfSSL download fails

**Solution:**
```bash
# Verify password file
cat wolfssl_password.txt

# Check permissions
chmod 600 wolfssl_password.txt
```

**Problem:** Build fails with insufficient memory

**Solution:**
```bash
# Increase Docker memory to 4GB+
# Docker Desktop: Settings → Resources → Memory
```

### Runtime Issues

**Problem:** Test 5 shows "PostgreSQL requires authentication" or SHA-256/SHA-512 tests fail

**Cause:** The test-provider.sh script cannot connect to PostgreSQL without authentication.

**Solution:**
```bash
# Use -e PGPASSWORD with your actual PostgreSQL password
docker exec -e PGPASSWORD=SecurePassword123! postgresql-fips-ubuntu /usr/local/bin/test-provider.sh

# Or set it in your environment first
export PGPASSWORD=SecurePassword123!
docker exec -e PGPASSWORD postgresql-fips-ubuntu /usr/local/bin/test-provider.sh
```

**Verification:** With the correct password, you should see:
```
[Test 5/6] PostgreSQL cryptographic functions
-------------------------------------------
PostgreSQL is running - testing crypto functions...

Installing pgcrypto extension:
  ✓ pgcrypto extension available

Testing MD5 hash (via pgcrypto):
  ✓ MD5 correctly blocked (expected in FIPS mode)

Testing SHA-256 hash:
  ✓ SHA-256 hash successful

Testing SHA-512 hash:
  ✓ SHA-512 hash successful

Testing AES encryption (via pgcrypto):
  ✓ AES encryption successful
```

**Problem:** FIPS validation fails

**Solution:**
```bash
# Check logs for specific error (adjust container name)
docker logs postgresql-fips-ubuntu 2>&1 | grep -A 10 "ERROR"  # docker-compose
docker logs postgresql-fips 2>&1 | grep -A 10 "ERROR"  # docker run

# Verify environment
docker exec postgresql-fips-ubuntu env | grep OPENSSL  # docker-compose
docker exec postgresql-fips env | grep OPENSSL  # docker run

# Check provider installation
docker exec postgresql-fips-ubuntu ls -la /usr/local/lib64/ossl-modules/  # docker-compose
docker exec postgresql-fips ls -la /usr/local/lib64/ossl-modules/  # docker run
```

**Problem:** PostgreSQL won't start

**Solution:**
```bash
# Check container status
docker ps -a | grep postgresql-fips

# Check health status (adjust container name)
docker inspect postgresql-fips-ubuntu | grep -A 5 Health  # docker-compose
docker inspect postgresql-fips | grep -A 5 Health  # docker run

# View Bitnami logs
docker exec postgresql-fips-ubuntu cat /opt/bitnami/postgresql/logs/postgresql.log  # docker-compose
docker exec postgresql-fips cat /opt/bitnami/postgresql/logs/postgresql.log  # docker run
```

## Ubuntu-Specific Notes

### Package Differences from Debian

Ubuntu 22.04 uses different package names:

- `libssl3` (Ubuntu) vs `libssl3` (Debian)
- `libicu70` (Ubuntu) vs `libicu72` (Debian)

### System Dependencies

Runtime packages are specifically for Ubuntu 22.04:

- libc6 (2.39)
- OpenSSL system libraries (for NSS wrapper)
- ICU 74.x
- Other Ubuntu-specific versions

## Security Considerations

### FIPS Compliance

- Uses wolfSSL FIPS v5, a FIPS 140-3 validated module
- All cryptographic operations use FIPS-approved algorithms
- FIPS validation enforced at startup
- Container won't start if validation fails

### Security Hardening (Standard)

- Non-root user (UID 1001)
- SUID/SGID bits removed
- Minimal attack surface
- No build tools in runtime image
- Regular security updates applied

### STIG/CIS Hardening (Dockerfile.hardened)

Additional hardening measures in the hardened variant:

- Password policies (STIG UBTU-22-411015): 60-day max age, 7-day min age, SHA512 encryption
- Password complexity (STIG UBTU-22-611015/611020): 15-char minimum, character class requirements
- Failed login lockout (STIG UBTU-22-412010): 3 attempts, 15-minute lockout
- PAM faillock integration with audit logging
- Kernel parameter hardening (ASLR, ptrace restrictions, network stack protections)
- Audit rules for time changes, identity changes, authentication events
- SSH hardening (key-only auth, FIPS ciphers, connection limits)
- Sudo logging and session timeout
- File permission enforcement (644/640/600 based on sensitivity)
- System account shell restriction
- Core dump prevention
- Root login restrictions
- pgaudit extension for database activity logging

### Best Practices

1. **Always set POSTGRESQL_PASSWORD**
2. **Use Docker secrets in production**
3. **Restrict network access**
4. **Enable SSL/TLS for PostgreSQL**
5. **Regular image updates**
6. **Monitor logs for security events**

## File Structure

```
17.7.0-ubuntu-22.04/
├── Dockerfile                      # FIPS 140-3 build
├── Dockerfile.hardened             # FIPS + STIG/CIS build
├── build.sh                        # Standard build script
├── build-hardened.sh               # Hardened build script
├── docker-compose.yml              # Orchestration
├── fips-entrypoint.sh              # FIPS validation wrapper
├── openssl-wolfprov.cnf            # OpenSSL configuration
├── test-fips.c                     # Build-time test
├── fips-startup-check.c            # Runtime validator
├── test-provider.sh                # Provider test
├── .env.example                    # Environment template
├── .gitignore                      # Git exclusions
├── wolfssl_password.txt.example    # Password template
├── patches/                        # CVE patches (hardened only)
├── rootfs/                         # Bitnami scripts
├── prebuildfs/                     # Bitnami prebuild
├── init-scripts/                   # Initialization scripts
└── pre-init-scripts/               # Pre-initialization scripts
```

## Build Specifications

| Component | Dockerfile | Dockerfile.hardened |
|-----------|------------|---------------------|
| Build time | 25-35 min | 25-35 min |
| Image size | ~700-900MB | ~800-1000MB |
| Base OS | Ubuntu 22.04 | Ubuntu 22.04 |
| PostgreSQL | 17.7 | 17.7 |
| OpenSSL | 3.0.15 | 3.0.18 |
| wolfSSL | 5.8.2 FIPS v5.2.3 | 5.8.2 FIPS v5.2.3 |
| wolfProvider | v1.1.0 | v1.1.0 |
| STIG/CIS | No | Yes |
| pgaudit | No | Yes (v17.0) |
| CVE patches | No | Yes (gzip, util-linux) |

## Build Artifacts

### Standard Build Output

Standard FIPS build produces a container with OpenSSL 3.0.15, wolfSSL FIPS v5.2.3, and PostgreSQL 17.7. The build process generates FIPS validation artifacts in `/usr/local/bin/fips-startup-check` and comprehensive test scripts.

### Hardened Build Output

Hardened build produces all standard artifacts plus STIG/CIS compliance configurations in `/etc/security/`, `/etc/audit/`, `/etc/pam.d/`, and `/etc/sysctl.d/`. Custom-built binaries with CVE patches are installed to `/usr/bin/` and `/usr/sbin/`. The pgaudit extension is available at `/opt/bitnami/postgresql/lib/pgaudit.so` for database activity logging.

## Performance Notes

- FIPS cryptography adds 5-15% overhead to crypto operations
- FIPS validation adds ~2-3 seconds to startup time
- PostgreSQL performance unchanged for non-crypto operations
- Use connection pooling to minimize SSL handshakes

## Support

### Documentation

- README.md (this file)
- Dockerfile (inline comments)
- docker-compose.yml (usage examples)
- Bitnami PostgreSQL docs

### Reporting Issues

Include:

1. Build logs (if build issue)
2. Runtime logs: `docker logs <container-name>` (use `postgresql-fips-ubuntu` for docker-compose, `postgresql-fips` for docker run)
3. Environment: `docker exec <container-name> env`
4. Version: `docker exec <container-name> postgres --version`
5. FIPS validation output

## License

Based on Bitnami PostgreSQL (APACHE-2.0 License)

## Acknowledgments

- **Bitnami**: Original PostgreSQL Docker image and scripts
- **wolfSSL**: FIPS 140-3 validated cryptographic module
- **PostgreSQL**: Database software
- **OpenSSL**: Cryptographic library and provider framework
