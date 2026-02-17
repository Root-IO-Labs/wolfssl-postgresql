# PostgreSQL FIPS MD5 Authentication Tests

## Overview
This directory contains tests to verify that MD5 authentication is properly disabled for FIPS 140-3 compliance in the PostgreSQL FIPS Docker image.

## Running the Tests

### Automatic (Recommended)
The test script automatically detects the PostgreSQL password from the container:

```bash
./tests/test-md5-disabled.sh [container_name]
```

### With Explicit Password
You can also provide the password explicitly:

```bash
POSTGRES_PASSWORD=yourpass ./tests/test-md5-disabled.sh [container_name]
```

### Examples

```bash
# Test the default container (postgresql-fips)
./tests/test-md5-disabled.sh

# Test a specific container
./tests/test-md5-disabled.sh postgresql-fips-new

# Test with explicit password
POSTGRES_PASSWORD=testpass123 ./tests/test-md5-disabled.sh my-postgres-container
```

## Test Coverage

The test suite validates:

1. ✓ PostgreSQL binary built with MD5 patches
2. ✓ PostgreSQL service running correctly
3. ✓ password_encryption setting handled properly
4. ✓ MD5 password creation blocked
5. ✓ SCRAM-SHA-256 authentication works
6. ✓ SCRAM-SHA-256 password format verified
7. ✓ pg_hba.conf using scram-sha-256 (not md5)
8. ✓ FIPS compliance error messages present
9. ✓ Error messages suggest SCRAM-SHA-256 alternative

## Expected Results

All tests should pass (9/9) for a FIPS-compliant PostgreSQL installation:

```
========================================
Test Summary
========================================
Total Tests: 9
Passed: 9
Failed: 0

✓ All MD5 authentication disable tests PASSED

FIPS Compliance Status:
  ✓ MD5 authentication is disabled at source level
  ✓ MD5 password hash creation blocked
  ✓ SCRAM-SHA-256 authentication works correctly
  ✓ Error messages provide FIPS compliance guidance
```

## Troubleshooting

### "PostgreSQL Password Required" Error

If you see this error, the container requires authentication. Fix by:

1. Setting the password environment variable:
   ```bash
   POSTGRES_PASSWORD=yourpass ./tests/test-md5-disabled.sh container_name
   ```

2. Or ensuring the container has `POSTGRESQL_PASSWORD` set:
   ```bash
   docker run -e POSTGRESQL_PASSWORD=yourpass postgresql-fips-ubuntu:17.7.0
   ```

### Container Not Found

Ensure the container is running:
```bash
docker ps | grep postgresql
```

### Tests Failing

If tests fail, check:
- The patch was applied during build (check build logs)
- The Bitnami scripts were updated to use scram-sha-256
- The container is using the correct image version
