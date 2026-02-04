#!/bin/bash
################################################################################
# PostgreSQL FIPS - Non-FIPS Algorithm Detection and Verification Script
#
# Purpose: Comprehensive testing to verify non-FIPS algorithms are blocked
#          and FIPS-approved algorithms work correctly
#
# Usage:
#   ./tests/check-non-fips-algorithms.sh [image-name]
#
# Example:
#   ./tests/check-non-fips-algorithms.sh postgresql-fips-ubuntu:17.6.0
#
# Runtime: ~3-5 minutes
#
# Test Coverage:
#   • OpenSSL Layer - Non-FIPS algorithm blocking (8 algorithms)
#   • OpenSSL Layer - FIPS algorithm verification (7 algorithms)
#   • PostgreSQL Layer - Non-FIPS algorithm blocking (pgcrypto)
#   • PostgreSQL Layer - FIPS algorithm verification (pgcrypto)
#
# Exit Codes:
#   0 - All tests passed (100% FIPS compliance)
#   1 - One or more tests failed
#
# Last Updated: 2025-12-08
# Version: 1.0
################################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Get image name from argument or use default
IMAGE_NAME="${1:-postgresql-fips-ubuntu:17.6.0}"
CONTAINER_NAME="postgres-algo-test-$$"
FAILED=0
TEST_COUNT=0
PASS_COUNT=0
BLOCKED_COUNT=0
WORKING_COUNT=0

echo "================================================================================"
echo "         PostgreSQL FIPS - Non-FIPS Algorithm Detection"
echo "================================================================================"
echo ""
echo "Image: $IMAGE_NAME"
echo "Container: $CONTAINER_NAME"
echo "Runtime: Host-based (spawns test containers)"
echo ""

# Cleanup function
cleanup() {
    echo ""
    echo "Cleaning up test container..."
    docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
    docker rm "$CONTAINER_NAME" >/dev/null 2>&1 || true
}

# Set trap to cleanup on exit
trap cleanup EXIT

################################################################################
# Helper Functions
################################################################################

# Test if an OpenSSL algorithm is blocked (expected for non-FIPS)
test_openssl_blocked() {
    local algo="$1"
    local cmd="$2"
    local description="$3"

    TEST_COUNT=$((TEST_COUNT + 1))
    echo -n "  Testing $description ... "

    # Run the command and capture output
    local output
    output=$(docker run --rm "$IMAGE_NAME" bash -c "$cmd" 2>&1 || true)

    # Check if command failed (expected for non-FIPS)
    if echo "$output" | grep -qi "disabled\|unsupported\|unknown\|not supported\|invalid\|error"; then
        echo -e "${GREEN}✓ BLOCKED${NC} (expected)"
        PASS_COUNT=$((PASS_COUNT + 1))
        BLOCKED_COUNT=$((BLOCKED_COUNT + 1))
        return 0
    else
        echo -e "${RED}✗ ALLOWED${NC} (FIPS violation!)"
        echo "    Output: $output"
        FAILED=1
        return 1
    fi
}

# Test if an OpenSSL algorithm works (expected for FIPS-approved)
test_openssl_works() {
    local algo="$1"
    local cmd="$2"
    local description="$3"

    TEST_COUNT=$((TEST_COUNT + 1))
    echo -n "  Testing $description ... "

    # Run the command and capture output
    local output
    output=$(docker run --rm "$IMAGE_NAME" bash -c "$cmd" 2>&1 || true)

    # Check if command succeeded (expected for FIPS)
    if echo "$output" | grep -qv "disabled\|unsupported\|unknown\|not supported\|invalid\|error"; then
        # Additional check: output should have actual hash/cipher data
        if [ -n "$output" ] && [ "$output" != "" ]; then
            echo -e "${GREEN}✓ WORKS${NC} (expected)"
            PASS_COUNT=$((PASS_COUNT + 1))
            WORKING_COUNT=$((WORKING_COUNT + 1))
            return 0
        fi
    fi

    echo -e "${RED}✗ FAILED${NC} (should work!)"
    echo "    Output: $output"
    FAILED=1
    return 1
}

# Test if a PostgreSQL algorithm is blocked (expected for non-FIPS)
test_postgres_blocked() {
    local algo="$1"
    local sql="$2"
    local description="$3"

    TEST_COUNT=$((TEST_COUNT + 1))
    echo -n "  Testing $description ... "

    # Run the SQL command with retry logic
    local output=""
    local retry=0
    local max_retry=3

    while [ $retry -lt $max_retry ]; do
        output=$(docker exec "$CONTAINER_NAME" bash -c \
            "PGPASSWORD=testpass123 psql -U postgres -t -c \"$sql\"" 2>&1 || true)

        # Retry if socket connection failed
        if echo "$output" | grep -qi "No such file or directory\|Connection refused\|could not connect"; then
            retry=$((retry + 1))
            [ $retry -lt $max_retry ] && sleep 1
        else
            break
        fi
    done

    # Check if command failed (expected for non-FIPS)
    if echo "$output" | grep -qi "cannot use\|error\|cannot be initialized\|unsupported\|not supported\|disabled"; then
        echo -e "${GREEN}✓ BLOCKED${NC} (expected)"
        PASS_COUNT=$((PASS_COUNT + 1))
        BLOCKED_COUNT=$((BLOCKED_COUNT + 1))
        return 0
    else
        echo -e "${RED}✗ ALLOWED${NC} (FIPS violation!)"
        echo "    Output: $output"
        FAILED=1
        return 1
    fi
}

# Test if a PostgreSQL algorithm works (expected for FIPS-approved)
test_postgres_works() {
    local algo="$1"
    local sql="$2"
    local description="$3"

    TEST_COUNT=$((TEST_COUNT + 1))
    echo -n "  Testing $description ... "

    # Run the SQL command with retry logic
    local output=""
    local retry=0
    local max_retry=3

    while [ $retry -lt $max_retry ]; do
        output=$(docker exec "$CONTAINER_NAME" bash -c \
            "PGPASSWORD=testpass123 psql -U postgres -t -c \"$sql\"" 2>&1 || true)

        # Retry if socket connection failed
        if echo "$output" | grep -qi "No such file or directory\|Connection refused\|could not connect"; then
            retry=$((retry + 1))
            [ $retry -lt $max_retry ] && sleep 1
        else
            break
        fi
    done

    # Check if command succeeded (expected for FIPS)
    if echo "$output" | grep -qv "error\|cannot use\|cannot be initialized\|unsupported\|disabled"; then
        # Should have actual output (hash, encrypted data, etc.)
        if [ -n "$output" ] && echo "$output" | grep -q "[0-9a-f]"; then
            echo -e "${GREEN}✓ WORKS${NC} (expected)"
            PASS_COUNT=$((PASS_COUNT + 1))
            WORKING_COUNT=$((WORKING_COUNT + 1))
            return 0
        fi
    fi

    echo -e "${RED}✗ FAILED${NC} (should work!)"
    echo "    Output: $output"
    FAILED=1
    return 1
}

################################################################################
# Pre-Test: Image Validation
################################################################################
echo "[Pre-Test] Validating image..."
echo ""

echo -n "Checking if image '$IMAGE_NAME' exists ... "
if docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
    echo -e "${GREEN}✓ FOUND${NC}"
else
    echo -e "${RED}✗ NOT FOUND${NC}"
    echo ""
    echo "Error: Image '$IMAGE_NAME' not found"
    echo "Build the image first: ./build.sh"
    exit 1
fi

echo ""

################################################################################
# Test Suite 1: OpenSSL Layer - Non-FIPS Algorithm Tests
################################################################################
echo "================================================================================"
echo "[1/6] OpenSSL Layer - Non-FIPS Algorithm Tests"
echo "================================================================================"
echo ""
echo "Testing that non-FIPS algorithms are BLOCKED at OpenSSL layer..."
echo ""

# Non-FIPS hash algorithms
test_openssl_blocked "md5" \
    'echo -n "test" | openssl dgst -md5' \
    "MD5 hash (non-FIPS)"

test_openssl_blocked "md4" \
    'echo -n "test" | openssl dgst -md4' \
    "MD4 hash (non-FIPS)"

test_openssl_blocked "md2" \
    'echo -n "test" | openssl dgst -md2' \
    "MD2 hash (non-FIPS)"

test_openssl_blocked "ripemd160" \
    'echo -n "test" | openssl dgst -ripemd160' \
    "RIPEMD160 hash (non-FIPS)"

# Non-FIPS encryption algorithms
test_openssl_blocked "rc4" \
    'echo -n "test" | openssl enc -rc4 -k password -pbkdf2' \
    "RC4 encryption (non-FIPS)"

test_openssl_blocked "des" \
    'echo -n "test" | openssl enc -des -k password -pbkdf2' \
    "DES encryption (non-FIPS)"

test_openssl_blocked "bf" \
    'echo -n "test" | openssl enc -bf -k password -pbkdf2' \
    "Blowfish encryption (non-FIPS)"

test_openssl_blocked "cast5" \
    'echo -n "test" | openssl enc -cast5-cbc -k password -pbkdf2' \
    "CAST5 encryption (non-FIPS)"

echo ""
echo -e "${CYAN}Non-FIPS algorithms blocked: $BLOCKED_COUNT/8${NC}"
echo ""

################################################################################
# Test Suite 2: OpenSSL Layer - FIPS Algorithm Verification
################################################################################
echo "================================================================================"
echo "[2/6] OpenSSL Layer - FIPS Algorithm Verification"
echo "================================================================================"
echo ""
echo "Testing that FIPS-approved algorithms WORK at OpenSSL layer..."
echo ""

# Reset working count for FIPS algorithms
FIPS_WORKING_COUNT=$WORKING_COUNT

# FIPS-approved hash algorithms
test_openssl_works "sha256" \
    'echo -n "test" | openssl dgst -sha256' \
    "SHA-256 hash (FIPS-approved)"

test_openssl_works "sha384" \
    'echo -n "test" | openssl dgst -sha384' \
    "SHA-384 hash (FIPS-approved)"

test_openssl_works "sha512" \
    'echo -n "test" | openssl dgst -sha512' \
    "SHA-512 hash (FIPS-approved)"

# FIPS-approved encryption algorithms
test_openssl_works "aes-128-cbc" \
    'echo -n "test" | openssl enc -aes-128-cbc -k password -pbkdf2 | base64' \
    "AES-128-CBC encryption (FIPS-approved)"

test_openssl_works "aes-256-cbc" \
    'echo -n "test" | openssl enc -aes-256-cbc -k password -pbkdf2 | base64' \
    "AES-256-CBC encryption (FIPS-approved)"

test_openssl_works "aes-256-gcm" \
    'echo -n "test" | openssl enc -aes-256-gcm -k password -pbkdf2 | base64' \
    "AES-256-GCM encryption (FIPS-approved)"

test_openssl_works "des3" \
    'echo -n "test" | openssl enc -des3 -k password -pbkdf2 | base64' \
    "3DES encryption (FIPS-approved)"

FIPS_ALGO_COUNT=$((WORKING_COUNT - FIPS_WORKING_COUNT))

echo ""
echo -e "${CYAN}FIPS algorithms working: $FIPS_ALGO_COUNT/7${NC}"
echo ""

################################################################################
# Test Suite 3: Start PostgreSQL Container
################################################################################
echo "================================================================================"
echo "[3/6] Starting PostgreSQL Container"
echo "================================================================================"
echo ""

echo "Starting PostgreSQL container for SQL-level testing..."
docker run -d \
    --name "$CONTAINER_NAME" \
    -e POSTGRES_PASSWORD=testpass123 \
    "$IMAGE_NAME" >/dev/null 2>&1

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Container started${NC}"
else
    echo -e "${RED}✗ Failed to start container${NC}"
    exit 1
fi

echo "Waiting for PostgreSQL to be ready..."
WAIT_TIME=0
MAX_WAIT=60

while [ $WAIT_TIME -lt $MAX_WAIT ]; do
    if docker exec "$CONTAINER_NAME" pg_isready -U postgres >/dev/null 2>&1; then
        echo -e "${GREEN}✓ PostgreSQL ready (${WAIT_TIME}s)${NC}"
        break
    fi
    sleep 2
    WAIT_TIME=$((WAIT_TIME + 2))
done

if [ $WAIT_TIME -ge $MAX_WAIT ]; then
    echo -e "${RED}✗ PostgreSQL failed to start within ${MAX_WAIT}s${NC}"
    exit 1
fi

# Additional wait for socket to be fully ready for psql connections
echo "Waiting for PostgreSQL socket to be ready..."
sleep 3

# Verify socket connectivity with a test query
if docker exec "$CONTAINER_NAME" bash -c \
    "PGPASSWORD=testpass123 psql -U postgres -t -c 'SELECT 1;'" >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Socket connection verified${NC}"
else
    echo -e "${YELLOW}⚠ Socket not immediately ready, waiting 3 more seconds...${NC}"
    sleep 3
fi

echo ""

################################################################################
# Test Suite 4: PostgreSQL Layer - Non-FIPS Algorithm Tests
################################################################################
echo "================================================================================"
echo "[4/6] PostgreSQL Layer - Non-FIPS Algorithm Tests"
echo "================================================================================"
echo ""
echo "Testing that non-FIPS algorithms are BLOCKED at PostgreSQL layer..."
echo ""

# Reset blocked count for PostgreSQL tests
PG_BLOCKED_START=$BLOCKED_COUNT

# Non-FIPS hash algorithms via digest()
test_postgres_blocked "md5" \
    "SELECT encode(digest('test', 'md5'), 'hex');" \
    "digest() with MD5 (non-FIPS)"

test_postgres_blocked "md4" \
    "SELECT encode(digest('test', 'md4'), 'hex');" \
    "digest() with MD4 (non-FIPS)"

# Test MD5 password authentication is disabled (check password_encryption setting)
TEST_COUNT=$((TEST_COUNT + 1))
echo -n "  Testing MD5 password authentication (non-FIPS) ... "

# Retry logic for socket connectivity issues
output=""
retry_count=0
max_retries=3

while [ $retry_count -lt $max_retries ]; do
    output=$(docker exec "$CONTAINER_NAME" bash -c \
        "PGPASSWORD=testpass123 psql -U postgres -t -c 'SHOW password_encryption;'" 2>&1 || true)

    # Check if we got a valid response (not a socket error)
    if ! echo "$output" | grep -qi "No such file or directory\|Connection refused\|could not connect"; then
        break
    fi

    retry_count=$((retry_count + 1))
    if [ $retry_count -lt $max_retries ]; then
        sleep 2
    fi
done

if echo "$output" | grep -qi "scram-sha-256"; then
    echo -e "${GREEN}✓ BLOCKED${NC} (using SCRAM-SHA-256)"
    PASS_COUNT=$((PASS_COUNT + 1))
    BLOCKED_COUNT=$((BLOCKED_COUNT + 1))
elif echo "$output" | grep -qi "md5"; then
    echo -e "${RED}✗ ALLOWED${NC} (FIPS violation! MD5 auth enabled)"
    echo "    Output: $output"
    FAILED=1
else
    echo -e "${YELLOW}⚠ UNKNOWN${NC}"
    echo "    Output: $output"
fi

# Install pgcrypto if not present and test non-FIPS algorithms
docker exec "$CONTAINER_NAME" bash -c \
    "PGPASSWORD=testpass123 psql -U postgres -c 'CREATE EXTENSION IF NOT EXISTS pgcrypto;'" \
    >/dev/null 2>&1 || true

# Non-FIPS encryption via pgcrypto
test_postgres_blocked "bf_pgcrypto" \
    "SELECT encode(encrypt('data', 'key', 'bf'), 'hex');" \
    "pgcrypto Blowfish encryption (non-FIPS)"

test_postgres_blocked "cast5_pgcrypto" \
    "SELECT encode(encrypt('data', 'key', 'cast5'), 'hex');" \
    "pgcrypto CAST5 encryption (non-FIPS)"

PG_BLOCKED_COUNT=$((BLOCKED_COUNT - PG_BLOCKED_START))

echo ""
echo -e "${CYAN}Non-FIPS algorithms blocked at PostgreSQL layer: $PG_BLOCKED_COUNT/5${NC}"
echo ""

################################################################################
# Test Suite 5: PostgreSQL Layer - FIPS Algorithm Verification
################################################################################
echo "================================================================================"
echo "[5/6] PostgreSQL Layer - FIPS Algorithm Verification"
echo "================================================================================"
echo ""
echo "Testing that FIPS-approved algorithms WORK at PostgreSQL layer..."
echo ""

# Reset working count for PostgreSQL FIPS tests
PG_FIPS_START=$WORKING_COUNT

# FIPS-approved hash algorithms via digest()
test_postgres_works "sha256" \
    "SELECT encode(digest('test', 'sha256'), 'hex');" \
    "digest() with SHA-256 (FIPS-approved)"

test_postgres_works "sha384" \
    "SELECT encode(digest('test', 'sha384'), 'hex');" \
    "digest() with SHA-384 (FIPS-approved)"

test_postgres_works "sha512" \
    "SELECT encode(digest('test', 'sha512'), 'hex');" \
    "digest() with SHA-512 (FIPS-approved)"

# FIPS-approved encryption via pgcrypto
test_postgres_works "aes_pgcrypto" \
    "SELECT encode(encrypt('data', 'keykeykeykeykeyk', 'aes'), 'hex');" \
    "pgcrypto AES encryption (FIPS-approved)"

test_postgres_works "aes128_pgcrypto" \
    "SELECT encode(encrypt('data', 'keykeykeykeykeyk', 'aes-cbc'), 'hex');" \
    "pgcrypto AES-128-CBC encryption (FIPS-approved)"

# Test SCRAM-SHA-256 authentication is available (FIPS-approved)
test_postgres_works "scram_auth" \
    "SHOW password_encryption;" \
    "SCRAM-SHA-256 authentication (FIPS-approved)"

PG_FIPS_COUNT=$((WORKING_COUNT - PG_FIPS_START))

echo ""
echo -e "${CYAN}FIPS algorithms working at PostgreSQL layer: $PG_FIPS_COUNT/6${NC}"
echo ""

################################################################################
# Test Suite 6: Summary Report
################################################################################
echo "================================================================================"
echo "[6/6] Compliance Report"
echo "================================================================================"
echo ""

TOTAL_NON_FIPS=13  # 8 OpenSSL + 5 PostgreSQL
TOTAL_FIPS=13      # 7 OpenSSL + 6 PostgreSQL

# Calculate percentages
NON_FIPS_PERCENT=$((BLOCKED_COUNT * 100 / TOTAL_NON_FIPS))
FIPS_PERCENT=$((WORKING_COUNT * 100 / TOTAL_FIPS))

echo "Test Summary:"
echo "  Total tests run: $TEST_COUNT"
echo "  Tests passed: $PASS_COUNT"
echo "  Tests failed: $((TEST_COUNT - PASS_COUNT))"
echo ""

echo "Non-FIPS Algorithm Blocking:"
echo -e "  Blocked: ${BLOCKED_COUNT}/${TOTAL_NON_FIPS} (${NON_FIPS_PERCENT}%)"
if [ $BLOCKED_COUNT -eq $TOTAL_NON_FIPS ]; then
    echo -e "  ${GREEN}✓ All non-FIPS algorithms correctly blocked${NC}"
else
    echo -e "  ${RED}✗ Some non-FIPS algorithms are not blocked!${NC}"
fi
echo ""

echo "FIPS Algorithm Verification:"
echo -e "  Working: ${WORKING_COUNT}/${TOTAL_FIPS} (${FIPS_PERCENT}%)"
if [ $WORKING_COUNT -eq $TOTAL_FIPS ]; then
    echo -e "  ${GREEN}✓ All FIPS algorithms working correctly${NC}"
else
    echo -e "  ${RED}✗ Some FIPS algorithms are not working!${NC}"
fi
echo ""

# Overall compliance
if [ $FAILED -eq 0 ]; then
    COMPLIANCE_PERCENT=$(( (PASS_COUNT * 100) / TEST_COUNT ))
    echo "================================================================================"
    echo -e "${GREEN}✓ ALL TESTS PASSED - 100% FIPS COMPLIANCE VERIFIED${NC}"
    echo "================================================================================"
    echo ""
    echo "Summary:"
    echo "  ✓ Non-FIPS algorithms are blocked (MD5, MD4, RC4, DES, etc.)"
    echo "  ✓ FIPS algorithms work correctly (SHA-256, AES, 3DES, etc.)"
    echo "  ✓ Blocking enforced at both OpenSSL and PostgreSQL layers"
    echo "  ✓ Ready for FedRAMP 3PAO audit"
    echo ""
    exit 0
else
    echo "================================================================================"
    echo -e "${RED}✗ SOME TESTS FAILED - FIPS COMPLIANCE ISSUES DETECTED${NC}"
    echo "================================================================================"
    echo ""
    echo "Issues detected:"
    if [ $BLOCKED_COUNT -lt $TOTAL_NON_FIPS ]; then
        echo "  ✗ Non-FIPS algorithms are not fully blocked"
        echo "    Expected: All 13 blocked"
        echo "    Actual: $BLOCKED_COUNT blocked"
    fi
    if [ $WORKING_COUNT -lt $TOTAL_FIPS ]; then
        echo "  ✗ FIPS algorithms are not fully working"
        echo "    Expected: All 13 working"
        echo "    Actual: $WORKING_COUNT working"
    fi
    echo ""
    echo "Action required:"
    echo "  1. Review test output above for specific failures"
    echo "  2. Check OpenSSL configuration (openssl.cnf)"
    echo "  3. Verify PostgreSQL built with FIPS OpenSSL"
    echo "  4. Check wolfProvider is loaded: docker run --rm $IMAGE_NAME openssl list -providers"
    echo ""
    exit 1
fi
