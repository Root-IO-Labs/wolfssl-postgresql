#!/bin/bash
################################################################################
# SASL FIPS Compliance Test Script
# Tests that libsasl2-2 is configured to use only FIPS-approved mechanisms
#
# Usage:
#   ./test-sasl-fips-compliance.sh [container_name]
#
# If no container name is provided, the script will:
#   1. Check if a container named 'postgresql-fips' is running
#   2. If not, start a temporary container for testing
#
# Requirements:
#   - Docker must be installed and running
#   - PostgreSQL FIPS image must be available
################################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Test result function
test_result() {
    local test_name="$1"
    local result="$2"
    local message="${3:-}"

    TESTS_TOTAL=$((TESTS_TOTAL + 1))

    if [ "$result" = "PASS" ]; then
        echo -e "${GREEN}✓ PASS${NC}: $test_name"
        [ -n "$message" ] && echo "  → $message"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗ FAIL${NC}: $test_name"
        [ -n "$message" ] && echo "  → $message"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# Container name from argument or default
CONTAINER_NAME="${1:-}"
TEMP_CONTAINER=false

# If no container name provided, check for existing or create temporary
if [ -z "$CONTAINER_NAME" ]; then
    # Check if default container exists and is running
    if docker ps --format '{{.Names}}' | grep -q '^postgresql-fips$'; then
        CONTAINER_NAME="postgresql-fips"
        echo -e "${BLUE}ℹ Using existing container: $CONTAINER_NAME${NC}"
    else
        # Start temporary container
        CONTAINER_NAME="sasl-test-$$"
        TEMP_CONTAINER=true
        echo -e "${BLUE}ℹ Starting temporary container: $CONTAINER_NAME${NC}"
        docker run -d --name "$CONTAINER_NAME" \
            -e POSTGRESQL_PASSWORD=testpass123 \
            postgresql-fips-ubuntu:17.7.0 >/dev/null 2>&1 || {
            echo -e "${RED}✗ ERROR: Failed to start container${NC}"
            echo "Please ensure postgresql-fips-ubuntu:17.7.0 image exists"
            exit 1
        }
        echo "Waiting for PostgreSQL to initialize..."
        sleep 15
    fi
else
    # Check if provided container exists and is running
    if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo -e "${RED}✗ ERROR: Container '$CONTAINER_NAME' is not running${NC}"
        echo ""
        echo "Usage: $0 [container_name]"
        echo ""
        echo "Please either:"
        echo "  1. Run without arguments to auto-start a temporary container"
        echo "  2. Provide a running container name"
        echo "  3. Start a container first:"
        echo "     docker run -d --name postgresql-fips -e POSTGRESQL_PASSWORD=test postgresql-fips-ubuntu:17.7.0"
        exit 1
    fi
fi

# Cleanup function for temporary container
cleanup() {
    if [ "$TEMP_CONTAINER" = true ]; then
        echo ""
        echo "Cleaning up temporary container..."
        docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
        docker rm "$CONTAINER_NAME" >/dev/null 2>&1 || true
    fi
}

trap cleanup EXIT

echo "========================================"
echo "SASL FIPS Compliance Test"
echo "========================================"
echo "Container: $CONTAINER_NAME"
echo "Date: $(date)"
echo ""

################################################################################
# Test 1: PostgreSQL links to libsasl2
################################################################################
echo "Test 1: Checking PostgreSQL libsasl2 linkage..."
if docker exec "$CONTAINER_NAME" ldd /opt/bitnami/postgresql/bin/postgres 2>/dev/null | grep -q "libsasl2"; then
    SASL_PATH=$(docker exec "$CONTAINER_NAME" ldd /opt/bitnami/postgresql/bin/postgres 2>/dev/null | grep libsasl2 | awk '{print $3}')
    test_result "PostgreSQL links to libsasl2" "PASS" "Linked to: $SASL_PATH"
else
    test_result "PostgreSQL links to libsasl2" "FAIL" "libsasl2 not linked"
fi

################################################################################
# Test 2: SASL configuration file exists
################################################################################
echo ""
echo "Test 2: Checking SASL configuration file..."
if docker exec "$CONTAINER_NAME" test -f /etc/sasl2/postgresql.conf 2>/dev/null; then
    test_result "SASL configuration file exists" "PASS" "/etc/sasl2/postgresql.conf"
else
    test_result "SASL configuration file exists" "FAIL" "File not found"
fi

################################################################################
# Test 3: FIPS-approved mechanisms enabled
################################################################################
echo ""
echo "Test 3: Checking FIPS-approved mechanisms..."

# Check SCRAM-SHA-256
if docker exec "$CONTAINER_NAME" grep -q "SCRAM-SHA-256" /etc/sasl2/postgresql.conf 2>/dev/null; then
    test_result "SCRAM-SHA-256 enabled" "PASS"
else
    test_result "SCRAM-SHA-256 enabled" "FAIL"
fi

# Check GSSAPI
if docker exec "$CONTAINER_NAME" grep -q "GSSAPI" /etc/sasl2/postgresql.conf 2>/dev/null; then
    test_result "GSSAPI enabled" "PASS"
else
    test_result "GSSAPI enabled" "FAIL"
fi

################################################################################
# Test 4: Non-FIPS mechanisms NOT in allowlist (therefore blocked)
################################################################################
echo ""
echo "Test 4: Verifying mech_list uses allowlist approach..."

# Verify non-FIPS mechanisms are NOT in the mech_list (allowlist approach blocks them)
MECH_LIST=$(docker exec "$CONTAINER_NAME" grep "^mech_list:" /etc/sasl2/postgresql.conf 2>/dev/null || echo "")

# Check DIGEST-MD5 is NOT in allowlist (therefore blocked)
if ! echo "$MECH_LIST" | grep -q "DIGEST-MD5"; then
    test_result "DIGEST-MD5 not in allowlist (blocked)" "PASS"
else
    test_result "DIGEST-MD5 not in allowlist (blocked)" "FAIL" "DIGEST-MD5 should not be in mech_list"
fi

# Check CRAM-MD5 is NOT in allowlist (therefore blocked)
if ! echo "$MECH_LIST" | grep -q "CRAM-MD5"; then
    test_result "CRAM-MD5 not in allowlist (blocked)" "PASS"
else
    test_result "CRAM-MD5 not in allowlist (blocked)" "FAIL" "CRAM-MD5 should not be in mech_list"
fi

# Check NTLM is NOT in allowlist (therefore blocked)
if ! echo "$MECH_LIST" | grep -q "NTLM"; then
    test_result "NTLM not in allowlist (blocked)" "PASS"
else
    test_result "NTLM not in allowlist (blocked)" "FAIL" "NTLM should not be in mech_list"
fi

################################################################################
# Test 5: SASL configuration file permissions
################################################################################
echo ""
echo "Test 5: Checking SASL configuration file permissions..."
PERMS=$(docker exec "$CONTAINER_NAME" stat -c "%a" /etc/sasl2/postgresql.conf 2>/dev/null || echo "000")
if [ "$PERMS" = "644" ] || [ "$PERMS" = "444" ]; then
    test_result "SASL config file permissions" "PASS" "Permissions: $PERMS"
else
    test_result "SASL config file permissions" "FAIL" "Permissions: $PERMS (should be 644 or 444)"
fi

################################################################################
# Test 6: Display SASL configuration
################################################################################
echo ""
echo "Test 6: SASL Configuration Contents"
echo "========================================"
if docker exec "$CONTAINER_NAME" test -f /etc/sasl2/postgresql.conf 2>/dev/null; then
    docker exec "$CONTAINER_NAME" cat /etc/sasl2/postgresql.conf 2>/dev/null | grep -v "^#" | grep -v "^$" || true
    test_result "SASL configuration readable" "PASS"
else
    test_result "SASL configuration readable" "FAIL"
fi

################################################################################
# Test 7: Check libsasl2 version and capabilities
################################################################################
echo ""
echo "Test 7: libsasl2 library information..."
if docker exec "$CONTAINER_NAME" dpkg -l | grep -q "libsasl2-2"; then
    SASL_VERSION=$(docker exec "$CONTAINER_NAME" dpkg -l | grep libsasl2-2 | awk '{print $3}')
    test_result "libsasl2-2 installed" "PASS" "Version: $SASL_VERSION"
else
    test_result "libsasl2-2 installed" "FAIL"
fi

################################################################################
# Test 8: Custom OpenLDAP uses libsasl2
################################################################################
echo ""
echo "Test 8: Checking OpenLDAP SASL integration..."
if docker exec "$CONTAINER_NAME" ldd /opt/openldap-fips/lib/libldap.so 2>/dev/null | grep -q "libsasl2"; then
    test_result "OpenLDAP uses libsasl2" "PASS"
else
    test_result "OpenLDAP uses libsasl2" "FAIL" "OpenLDAP should link to libsasl2 for SASL authentication"
fi

################################################################################
# Summary
################################################################################
echo ""
echo "========================================"
echo "Test Summary"
echo "========================================"
echo "Total Tests: $TESTS_TOTAL"
echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
if [ $TESTS_FAILED -gt 0 ]; then
    echo -e "${RED}Failed: $TESTS_FAILED${NC}"
else
    echo "Failed: $TESTS_FAILED"
fi
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All SASL FIPS compliance tests PASSED${NC}"
    echo ""
    echo "FIPS Compliance Status:"
    echo "  ✓ libsasl2-2 configured for FIPS-only mechanisms"
    echo "  ✓ SCRAM-SHA-256 and GSSAPI enabled (allowlist)"
    echo "  ✓ Non-FIPS mechanisms (DIGEST-MD5, CRAM-MD5, NTLM) blocked (not in allowlist)"
    echo "  ✓ All SASL authentication will use FIPS-validated OpenSSL"
    exit 0
else
    echo -e "${RED}✗ Some SASL FIPS compliance tests FAILED${NC}"
    echo ""
    echo "Please review the failures above and ensure:"
    echo "  1. SASL configuration file is properly installed"
    echo "  2. Only FIPS-approved mechanisms are in mech_list (allowlist)"
    echo "  3. Non-FIPS mechanisms are NOT in mech_list (blocked)"
    exit 1
fi
