#!/bin/bash
##############################################################################
# Simple FIPS Function Removal Test
# Tests that non-FIPS functions are removed from pgcrypto
################################################################################

IMAGE=${1:-postgresql-fips-ubuntu:17.7.0}
CONTAINER="simple-test-$$"

echo "==========================================="
echo "FIPS Function Removal Test"
echo "==========================================="
echo "Image: $IMAGE"
echo ""

# Cleanup
cleanup() {
    docker rm -f "$CONTAINER" 2>/dev/null || true
}
trap cleanup EXIT

# Start container
echo "[1/4] Starting PostgreSQL..."
docker run -d --name "$CONTAINER" -e POSTGRESQL_PASSWORD=testpass123 "$IMAGE" >/dev/null
sleep 15

# Create extension
echo "[2/4] Creating pgcrypto extension..."
docker exec "$CONTAINER" bash -c "PGPASSWORD=testpass123 psql -U postgres -c 'CREATE EXTENSION pgcrypto;'" >/dev/null 2>&1

# Test 1: crypt() should not exist
echo "[3/4] Testing non-FIPS functions..."
echo ""
echo "Test 1: crypt() function"
CRYPT_RESULT=$(docker exec "$CONTAINER" bash -c "PGPASSWORD=testpass123 psql -U postgres -c \"SELECT crypt('password', 'salt');\"" 2>&1)
echo "$CRYPT_RESULT" | head -5
if echo "$CRYPT_RESULT" | grep -q "does not exist"; then
    echo "✓ PASS - crypt() correctly removed"
else
    echo "✗ FAIL - crypt() still exists"
fi
echo ""

# Test 2: gen_salt() should not exist
echo "Test 2: gen_salt() function"
GENSALT_RESULT=$(docker exec "$CONTAINER" bash -c "PGPASSWORD=testpass123 psql -U postgres -c \"SELECT gen_salt('bf');\"" 2>&1)
echo "$GENSALT_RESULT" | head -5
if echo "$GENSALT_RESULT" | grep -q "does not exist"; then
    echo "✓ PASS - gen_salt() correctly removed"
else
    echo "✗ FAIL - gen_salt() still exists"
fi
echo ""

# Test 3: digest() should work
echo "[4/4] Testing FIPS functions..."
echo ""
echo "Test 3: digest() function with SHA-256"
RESULT=$(docker exec "$CONTAINER" bash -c "PGPASSWORD=testpass123 psql -U postgres -t -c \"SELECT encode(digest('test', 'sha256'), 'hex');\"" 2>&1 | tr -d ' \n')
echo "Result: $RESULT"
EXPECTED="9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08"
if [ "$RESULT" = "$EXPECTED" ]; then
    echo "✓ PASS - digest() with SHA-256 works correctly"
else
    echo "✗ FAIL - digest() returned wrong hash (expected: $EXPECTED)"
fi

echo ""
echo "==========================================="
echo "Test Summary"
echo "==========================================="
echo "All tests completed. Check results above."
echo "==========================================="
