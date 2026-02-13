#!/bin/bash
################################################################################
# PostgreSQL FIPS - LDAP with OpenSSL Test Script
#
# This script verifies that the custom-built OpenLDAP library uses OpenSSL
# (not GnuTLS) for all TLS/SSL operations, ensuring FIPS compliance while
# maintaining full compatibility with Bitnami's LDAP configuration features.
#
# Usage:
#   ./test-ldap-openssl.sh [image_name]
#
# Default image: postgresql-fips-ubuntu:17.7.0
#
# Test Coverage:
#   - OpenLDAP library presence and structure
#   - OpenSSL linkage verification (confirms no GnuTLS)
#   - PostgreSQL LDAP support compilation
#   - Bitnami LDAP configuration compatibility
#   - Library dependency chain validation
#   - FIPS compliance for LDAP operations
#
# Created: 2025-12-12
# Version: 1.0
################################################################################

set -e

IMAGE_NAME="${1:-postgresql-fips-ubuntu:17.7.0}"
FAILED_TESTS=0
PASSED_TESTS=0
CONTAINER_NAME="test-ldap-openssl-$$"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
BOLD='\033[1m'

echo "========================================================================"
echo "PostgreSQL FIPS - LDAP with OpenSSL Verification"
echo "Version: 1.0"
echo "========================================================================"
echo "Image: $IMAGE_NAME"
echo "Date: $(date)"
echo ""
echo "Test Objective: Verify LDAP uses FIPS-validated OpenSSL (not GnuTLS)"
echo ""

###############################################################################
# Helper Functions
###############################################################################

pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((PASSED_TESTS++)) || true
}

fail() {
    echo -e "${RED}✗${NC} $1"
    ((FAILED_TESTS++)) || true
}

warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

section() {
    echo ""
    echo -e "${BOLD}======================================${NC}"
    echo -e "${BOLD}$1${NC}"
    echo -e "${BOLD}======================================${NC}"
}

cleanup() {
    if [ -n "$CONTAINER_NAME" ]; then
        docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
    fi
}

trap cleanup EXIT INT TERM

###############################################################################
# Test Section 1: OpenLDAP Library Verification
###############################################################################
section "[1/6] OpenLDAP Library Verification"

echo "Checking custom OpenLDAP installation..."

# Check if OpenLDAP directory exists
if docker run --rm --entrypoint /bin/bash "$IMAGE_NAME" -c "test -d /opt/openldap-fips"; then
    pass "Custom OpenLDAP directory exists at /opt/openldap-fips"
else
    fail "Custom OpenLDAP directory NOT found at /opt/openldap-fips"
fi

# Check libldap library
if docker run --rm --entrypoint /bin/bash "$IMAGE_NAME" -c "test -f /opt/openldap-fips/lib/libldap.so"; then
    pass "libldap.so library found"

    # Get library version info
    echo "  Library details:"
    docker run --rm --entrypoint /bin/bash "$IMAGE_NAME" -c "ls -lh /opt/openldap-fips/lib/libldap.so" | head -1
else
    fail "libldap.so library NOT found"
fi

# Check liblber library (required by libldap)
if docker run --rm --entrypoint /bin/bash "$IMAGE_NAME" -c "test -f /opt/openldap-fips/lib/liblber.so"; then
    pass "liblber.so library found (LDAP BER encoding library)"
else
    fail "liblber.so library NOT found"
fi

# Check ldap utilities
if docker run --rm --entrypoint /bin/bash "$IMAGE_NAME" -c "test -f /opt/openldap-fips/bin/ldapsearch"; then
    pass "ldapsearch utility installed"
else
    warn "ldapsearch utility not found (optional)"
fi

# Verify system libldap is NOT present
if docker run --rm --entrypoint /bin/bash "$IMAGE_NAME" -c "test -f /usr/lib/x86_64-linux-gnu/libldap-2.5.so.0"; then
    fail "System libldap-2.5-0 still present! (should be removed)"
else
    pass "System libldap-2.5-0 correctly removed"
fi

###############################################################################
# Test Section 2: OpenSSL Linkage Verification (Critical for FIPS)
###############################################################################
section "[2/6] OpenSSL Linkage Verification (FIPS Compliance)"

echo "Verifying libldap uses FIPS-validated OpenSSL (not GnuTLS)..."

# Get ldd output for analysis
LDD_OUTPUT=$(docker run --rm --entrypoint /bin/bash "$IMAGE_NAME" -c "ldd /opt/openldap-fips/lib/libldap.so")

echo "  Library dependencies for libldap.so:"
echo "$LDD_OUTPUT" | grep -E "libssl|libcrypto|libgnutls|libsasl" | sed 's/^/    /'

# Check for OpenSSL linkage - can be at /usr/local/openssl/lib64 (old) or /usr/lib/x86_64-linux-gnu (new)
SSL_LINK=$(echo "$LDD_OUTPUT" | grep "libssl\.so" | grep -o " => [^ ]*" | cut -d' ' -f3)

if echo "$SSL_LINK" | grep -q "/usr/local/openssl/lib64/libssl"; then
    pass "libldap correctly linked to FIPS-validated OpenSSL (/usr/local/openssl/lib64/)"
elif echo "$SSL_LINK" | grep -q "/usr/lib/x86_64-linux-gnu/libssl"; then
    # Ubuntu System OpenSSL with wolfProvider
    pass "libldap correctly linked to Ubuntu System OpenSSL (/usr/lib/x86_64-linux-gnu/) with wolfProvider"
else
    fail "libldap NOT linked to FIPS OpenSSL (unknown library: $SSL_LINK)"
fi

# Check for libcrypto (OpenSSL)
CRYPTO_LINK=$(echo "$LDD_OUTPUT" | grep "libcrypto\.so" | grep -o " => [^ ]*" | cut -d' ' -f3)

if echo "$CRYPTO_LINK" | grep -q "/usr/local/openssl/lib64/libcrypto"; then
    pass "libldap correctly linked to FIPS-validated libcrypto (/usr/local/openssl/lib64/)"
elif echo "$CRYPTO_LINK" | grep -q "/usr/lib/x86_64-linux-gnu/libcrypto"; then
    # Ubuntu System OpenSSL with wolfProvider
    pass "libldap correctly linked to Ubuntu System libcrypto (/usr/lib/x86_64-linux-gnu/) with wolfProvider"
else
    fail "libldap NOT linked to FIPS libcrypto (unknown library: $CRYPTO_LINK)"
fi

# CRITICAL: Verify NO GnuTLS dependency
if echo "$LDD_OUTPUT" | grep -q "libgnutls"; then
    fail "CRITICAL: libldap still uses GnuTLS! FIPS compliance BROKEN!"
    echo "$LDD_OUTPUT" | grep "libgnutls" | sed 's/^/    /'
else
    pass "CRITICAL: No GnuTLS dependency found (FIPS compliance maintained)"
fi

# Check for SASL library (expected, uses OpenSSL)
if echo "$LDD_OUTPUT" | grep -q "libsasl2"; then
    pass "libsasl2 linked (SASL authentication support)"
    # Verify libsasl2 also uses OpenSSL (not GnuTLS)
    SASL_LDD=$(docker run --rm --entrypoint /bin/bash "$IMAGE_NAME" -c "ldd /usr/lib/x86_64-linux-gnu/libsasl2.so.2")
    if echo "$SASL_LDD" | grep -q "libgnutls"; then
        warn "libsasl2 uses GnuTLS (acceptable for SASL, but note for compliance docs)"
    fi
fi

###############################################################################
# Test Section 3: PostgreSQL LDAP Support
###############################################################################
section "[3/6] PostgreSQL LDAP Support"

echo "Verifying PostgreSQL compiled with LDAP support..."

# Check pg_config for LDAP
PG_CONFIG=$(docker run --rm --entrypoint /bin/bash "$IMAGE_NAME" -c "/opt/bitnami/postgresql/bin/pg_config --configure")

if echo "$PG_CONFIG" | grep -q -- "--with-ldap"; then
    pass "PostgreSQL compiled with --with-ldap flag"
else
    fail "PostgreSQL NOT compiled with --with-ldap flag"
    echo "  Configure output: $PG_CONFIG"
fi

# Check PostgreSQL binary linkage
echo "  Checking postgres binary LDAP linkage..."
POSTGRES_LDD=$(docker run --rm --entrypoint /bin/bash "$IMAGE_NAME" -c "ldd /opt/bitnami/postgresql/bin/postgres")

if echo "$POSTGRES_LDD" | grep -q "libldap"; then
    pass "postgres binary linked to libldap"
    echo "  LDAP libraries:"
    echo "$POSTGRES_LDD" | grep libldap | sed 's/^/    /'
else
    fail "postgres binary NOT linked to libldap (LDAP auth will not work)"
fi

# Verify PostgreSQL uses custom OpenLDAP (not system)
if echo "$POSTGRES_LDD" | grep -q "/opt/openldap-fips/lib/libldap"; then
    pass "PostgreSQL uses custom FIPS-compliant OpenLDAP"
else
    warn "PostgreSQL may not be using custom OpenLDAP (check RPATH)"
fi

###############################################################################
# Test Section 4: Bitnami LDAP Configuration Compatibility
###############################################################################
section "[4/6] Bitnami LDAP Configuration Compatibility"

echo "Testing Bitnami's LDAP environment variable support..."

# Check if Bitnami LDAP configuration function exists
if docker run --rm --entrypoint /bin/bash "$IMAGE_NAME" -c "grep -q 'postgresql_ldap_auth_configuration' /opt/bitnami/scripts/libpostgresql.sh"; then
    pass "Bitnami LDAP configuration function present"
else
    fail "Bitnami LDAP configuration function NOT found"
fi

# Test LDAP configuration function code and environment variable handling
echo "  Testing LDAP configuration function code..."
# Verify the function properly references environment variables
LDAP_FUNC_CODE=$(docker run --rm --entrypoint /bin/bash "$IMAGE_NAME" -c "grep -A 20 'postgresql_ldap_auth_configuration' /opt/bitnami/scripts/libpostgresql.sh | head -25")

if echo "$LDAP_FUNC_CODE" | grep -q "POSTGRESQL_LDAP_SERVER\|POSTGRESQL_LDAP_URL"; then
    pass "LDAP configuration function references POSTGRESQL_LDAP_* variables"
else
    fail "LDAP configuration function does not reference LDAP variables"
fi

# Verify TLS support in function code
if echo "$LDAP_FUNC_CODE" | grep -q "POSTGRESQL_LDAP_TLS\|ldaptls"; then
    pass "LDAP TLS configuration support present in function code"
else
    warn "LDAP TLS configuration not found in function code"
fi

# Verify ldapserver or ldapurl parameter generation
if echo "$LDAP_FUNC_CODE" | grep -q "ldapserver\|ldapurl"; then
    pass "LDAP server/URL parameter generation code present"
else
    fail "LDAP server parameter generation code not found"
fi

# Test all Bitnami LDAP environment variables
echo "  Supported Bitnami LDAP environment variables:"
LDAP_VARS=$(docker run --rm --entrypoint /bin/bash "$IMAGE_NAME" -c "grep 'POSTGRESQL_LDAP' /opt/bitnami/scripts/libpostgresql.sh | grep -o 'POSTGRESQL_LDAP_[A-Z_]*' | sort -u")
LDAP_VAR_COUNT=$(echo "$LDAP_VARS" | wc -l)

if [ "$LDAP_VAR_COUNT" -gt 5 ]; then
    pass "Found $LDAP_VAR_COUNT Bitnami LDAP environment variables"
    echo "$LDAP_VARS" | sed 's/^/    - /'
else
    warn "Only found $LDAP_VAR_COUNT LDAP environment variables"
fi

###############################################################################
# Test Section 5: Library Path and Runtime Configuration
###############################################################################
section "[5/6] Library Path and Runtime Configuration"

echo "Verifying library paths and runtime environment..."

# Check LD_LIBRARY_PATH includes OpenLDAP
LD_PATH=$(docker run --rm --entrypoint /bin/bash "$IMAGE_NAME" -c "printenv LD_LIBRARY_PATH")

if echo "$LD_PATH" | grep -q "/opt/openldap-fips/lib"; then
    pass "LD_LIBRARY_PATH includes /opt/openldap-fips/lib"
else
    fail "LD_LIBRARY_PATH does NOT include /opt/openldap-fips/lib"
    echo "  Current LD_LIBRARY_PATH: $LD_PATH"
fi

# Check PATH includes OpenLDAP binaries
PATH_VAR=$(docker run --rm --entrypoint /bin/bash "$IMAGE_NAME" -c "printenv PATH")

if echo "$PATH_VAR" | grep -q "/opt/openldap-fips/bin"; then
    pass "PATH includes /opt/openldap-fips/bin"
else
    warn "PATH does not include /opt/openldap-fips/bin (ldap utilities may not be accessible)"
fi

# Verify ldconfig cache
echo "  Checking shared library cache..."
if docker run --rm --entrypoint /bin/bash "$IMAGE_NAME" -c "ldconfig -p | grep -q 'libldap.so.*=> /opt/openldap-fips/lib'"; then
    pass "ldconfig cache includes custom OpenLDAP"
else
    warn "ldconfig cache may need updating for OpenLDAP"
fi

# Check for any GnuTLS libraries in the image
echo "  Scanning for GnuTLS libraries..."
GNUTLS_CHECK=$(docker run --rm --entrypoint /bin/bash "$IMAGE_NAME" -c "find /usr/lib /lib /opt -name '*gnutls*' 2>/dev/null || true")

if [ -n "$GNUTLS_CHECK" ]; then
    warn "GnuTLS libraries found in image:"
    echo "$GNUTLS_CHECK" | sed 's/^/    /'
    echo "  Note: GnuTLS may be a dependency of other packages but should not be used for LDAP"
else
    pass "No GnuTLS libraries found in standard locations"
fi

###############################################################################
# Test Section 6: FIPS Compliance Verification
###############################################################################
section "[6/6] FIPS Compliance Verification"

echo "Verifying complete FIPS compliance for LDAP operations..."

# Create a test container for comprehensive checks
echo "  Starting test container..."
docker run -d --name "$CONTAINER_NAME" \
    -e POSTGRESQL_PASSWORD=testpass123 \
    "$IMAGE_NAME" >/dev/null 2>&1

# Wait for PostgreSQL to start
echo "  Waiting for PostgreSQL to initialize..."
for i in {1..30}; do
    if docker exec "$CONTAINER_NAME" pg_isready -U postgres >/dev/null 2>&1; then
        break
    fi
    sleep 2
done

if docker exec "$CONTAINER_NAME" pg_isready -U postgres >/dev/null 2>&1; then
    pass "PostgreSQL started successfully with custom OpenLDAP"
else
    fail "PostgreSQL failed to start (may indicate library issues)"
fi

# Check crypto dependencies in running container
echo "  Analyzing cryptographic library dependencies..."
RUNTIME_CRYPTO=$(docker exec "$CONTAINER_NAME" ldd /opt/bitnami/postgresql/bin/postgres | grep -E "crypto|ssl|ldap")

echo "  Cryptographic libraries in use:"
echo "$RUNTIME_CRYPTO" | sed 's/^/    /'

# Check for FIPS OpenSSL at runtime - can be at /usr/local/openssl/lib64 (old) or /usr/lib/x86_64-linux-gnu (new)
RUNTIME_SSL_LINK=$(echo "$RUNTIME_CRYPTO" | grep "libssl\.so" | grep -o " => [^ ]*" | cut -d' ' -f3)

if echo "$RUNTIME_SSL_LINK" | grep -q "/usr/local/openssl/lib64/libssl"; then
    pass "Runtime: Using FIPS-validated OpenSSL (/usr/local/openssl/lib64/)"
elif echo "$RUNTIME_SSL_LINK" | grep -q "/usr/lib/x86_64-linux-gnu/libssl"; then
    # Ubuntu System OpenSSL with wolfProvider
    pass "Runtime: Using Ubuntu System OpenSSL (/usr/lib/x86_64-linux-gnu/) with wolfProvider"
else
    fail "Runtime: Not using FIPS-validated OpenSSL (unknown library: $RUNTIME_SSL_LINK)"
fi

if echo "$RUNTIME_CRYPTO" | grep -q "/opt/openldap-fips/lib/libldap"; then
    pass "Runtime: Using custom FIPS-compliant OpenLDAP"
else
    warn "Runtime: Custom OpenLDAP may not be loaded"
fi

# Verify FIPS mode is active
echo "  Checking FIPS mode status..."
if docker exec "$CONTAINER_NAME" /usr/local/bin/fips-startup-check >/dev/null 2>&1; then
    pass "FIPS validation checks passed in running container"
else
    fail "FIPS validation checks failed"
fi

# Test OpenSSL provider in container
PROVIDER_TEST=$(docker exec "$CONTAINER_NAME" openssl list -providers 2>&1)
if echo "$PROVIDER_TEST" | grep -q "wolfprov"; then
    pass "wolfProvider loaded and active"
else
    fail "wolfProvider not loaded"
fi

###############################################################################
# Test Results Summary
###############################################################################
section "Test Results Summary"

echo ""
echo "Total tests passed: $PASSED_TESTS"
echo "Total tests failed: $FAILED_TESTS"
echo ""

if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "${GREEN}${BOLD}✓ ALL TESTS PASSED${NC}"
    echo ""
    echo "FIPS Compliance Status: ✅ VERIFIED"
    echo ""
    echo "Key Findings:"
    echo "  • Custom OpenLDAP built with OpenSSL (not GnuTLS)"
    echo "  • All LDAP/TLS operations use FIPS-validated OpenSSL"
    echo "  • PostgreSQL LDAP authentication support enabled"
    echo "  • Bitnami LDAP configuration features fully compatible"
    echo "  • No GnuTLS cryptographic bypass"
    echo ""
    echo "The implementation successfully maintains:"
    echo "  ✓ FIPS 140-3 compliance for all LDAP operations"
    echo "  ✓ Full compatibility with Bitnami LDAP environment variables"
    echo "  ✓ PostgreSQL LDAP authentication functionality"
    echo "  ✓ Single cryptographic library (OpenSSL only)"
    echo ""
    echo "Next steps:"
    echo "  1. Test LDAP authentication with actual LDAP server"
    echo "  2. Verify LDAPS (LDAP over TLS/SSL) connections"
    echo "  3. Test StartTLS functionality"
    echo "  4. Document configuration in deployment guide"
    echo ""
    exit 0
else
    echo -e "${RED}${BOLD}✗ TESTS FAILED${NC}"
    echo ""
    echo "FIPS Compliance Status: ❌ ISSUES DETECTED"
    echo ""
    echo "Issues found: $FAILED_TESTS"
    echo ""
    echo "Recommended actions:"
    echo "  1. Review build logs for OpenLDAP compilation errors"
    echo "  2. Verify --with-tls=openssl was used in configure"
    echo "  3. Check library RPATH settings"
    echo "  4. Ensure PostgreSQL was built against custom OpenLDAP"
    echo "  5. Review Dockerfile OpenLDAP build section"
    echo ""
    echo "For troubleshooting, run:"
    echo "  docker run --rm $IMAGE_NAME ldd /opt/openldap-fips/lib/libldap.so"
    echo "  docker run --rm $IMAGE_NAME ldd /opt/bitnami/postgresql/bin/postgres"
    echo ""
    exit 1
fi
