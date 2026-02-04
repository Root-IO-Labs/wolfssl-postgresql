#!/bin/bash
################################################################################
# PostgreSQL FIPS - Disable Non-FIPS Functions
#
# This script removes non-FIPS cryptographic functions by commenting out
# their definitions in the pgcrypto extension SQL file.
#
# Functions removed:
# - crypt(text, text) - Uses Blowfish/MD5/DES
# - gen_salt(text) - Generates salts for non-FIPS algorithms
# - gen_salt(text, int) - Generates salts with rounds
################################################################################

set -e

PGCRYPTO_SQL_DIR="contrib/pgcrypto"

echo "=========================================="
echo "Disabling Non-FIPS pgcrypto Functions"
echo "=========================================="

# Find the main pgcrypto SQL file (not migration files)
# We want pgcrypto--1.3.sql (the full extension), not pgcrypto--1.2--1.3.sql (migration)
PGCRYPTO_SQL=$(find "$PGCRYPTO_SQL_DIR" -name "pgcrypto--[0-9].[0-9].sql" | sort -V | tail -1)

if [ -z "$PGCRYPTO_SQL" ]; then
    echo "ERROR: pgcrypto SQL file not found!"
    echo "Expected in: $PGCRYPTO_SQL_DIR"
    exit 1
fi

echo ""
echo "Found pgcrypto SQL file: $PGCRYPTO_SQL"
echo ""

# Backup original
cp "$PGCRYPTO_SQL" "${PGCRYPTO_SQL}.bak"
echo "Created backup: ${PGCRYPTO_SQL}.bak"
echo ""

################################################################################
# Comment out crypt() function
################################################################################
echo "[1/3] Disabling crypt(text, text) function..."

# The function definition spans multiple lines ending with PARALLEL SAFE;
# Format:
# CREATE FUNCTION crypt(text, text)
# RETURNS text
# AS 'MODULE_PATHNAME', 'pg_crypt'
# LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
sed -i '/^CREATE FUNCTION crypt(text, text)/,/PARALLEL SAFE;$/ {
    s/^/-- FIPS: /
}' "$PGCRYPTO_SQL"

if grep -q "^-- FIPS: CREATE FUNCTION crypt(text, text)" "$PGCRYPTO_SQL"; then
    echo "  ✓ crypt(text, text) disabled"
else
    echo "  ✗ Failed to disable crypt(text, text)"
    exit 1
fi

################################################################################
# Comment out gen_salt(text) function
################################################################################
echo ""
echo "[2/3] Disabling gen_salt(text) function..."

sed -i '/^CREATE FUNCTION gen_salt(text)$/,/PARALLEL SAFE;$/ {
    s/^/-- FIPS: /
}' "$PGCRYPTO_SQL"

if grep -q "^-- FIPS: CREATE FUNCTION gen_salt(text)" "$PGCRYPTO_SQL"; then
    echo "  ✓ gen_salt(text) disabled"
else
    echo "  ✗ Failed to disable gen_salt(text)"
    exit 1
fi

################################################################################
# Comment out gen_salt(text, int) function
################################################################################
echo ""
echo "[3/3] Disabling gen_salt(text, int4) function..."

sed -i '/^CREATE FUNCTION gen_salt(text, int4)$/,/PARALLEL SAFE;$/ {
    s/^/-- FIPS: /
}' "$PGCRYPTO_SQL"

if grep -q "^-- FIPS: CREATE FUNCTION gen_salt(text, int4)" "$PGCRYPTO_SQL"; then
    echo "  ✓ gen_salt(text, int4) disabled"
else
    echo "  ✗ Failed to disable gen_salt(text, int4)"
    exit 1
fi

################################################################################
# Verification
################################################################################
echo ""
echo "[4/4] Verifying modifications..."
echo ""

ERRORS=0

# Count commented functions
CRYPT_DISABLED=$(grep -c "^-- FIPS: CREATE FUNCTION crypt(text, text)" "$PGCRYPTO_SQL" || echo 0)
GEN_SALT_1_DISABLED=$(grep -c "^-- FIPS: CREATE FUNCTION gen_salt(text)" "$PGCRYPTO_SQL" || echo 0)
GEN_SALT_2_DISABLED=$(grep -c "^-- FIPS: CREATE FUNCTION gen_salt(text, int4)" "$PGCRYPTO_SQL" || echo 0)

if [ "$CRYPT_DISABLED" -eq 0 ]; then
    echo "  ✗ crypt(text, text) not commented out"
    ERRORS=$((ERRORS + 1))
else
    echo "  ✓ crypt(text, text) commented out"
fi

if [ "$GEN_SALT_1_DISABLED" -eq 0 ]; then
    echo "  ✗ gen_salt(text) not commented out"
    ERRORS=$((ERRORS + 1))
else
    echo "  ✓ gen_salt(text) commented out"
fi

if [ "$GEN_SALT_2_DISABLED" -eq 0 ]; then
    echo "  ✗ gen_salt(text, int4) not commented out"
    ERRORS=$((ERRORS + 1))
else
    echo "  ✓ gen_salt(text, int4) commented out"
fi

# Check that FIPS functions still exist (not accidentally commented)
echo ""
echo "Verifying FIPS-approved functions still available..."

FIPS_FUNCTIONS=(
    "digest(text, text)"
    "hmac(text, text, text)"
    "encrypt(bytea, bytea, text)"
    "decrypt(bytea, bytea, text)"
)

for func in "${FIPS_FUNCTIONS[@]}"; do
    if grep -q "^CREATE FUNCTION $func" "$PGCRYPTO_SQL"; then
        echo "  ✓ $func still available"
    else
        echo "  ✗ WARNING: $func may have been accidentally disabled"
        ERRORS=$((ERRORS + 1))
    fi
done

echo ""
if [ $ERRORS -eq 0 ]; then
    echo "=========================================="
    echo "✓ NON-FIPS FUNCTIONS DISABLED SUCCESSFULLY"
    echo "=========================================="
    echo ""
    echo "Summary of changes:"
    echo "  • crypt(text, text) - REMOVED"
    echo "  • gen_salt(text) - REMOVED"
    echo "  • gen_salt(text, int4) - REMOVED"
    echo ""
    echo "FIPS-approved functions remain available:"
    echo "  • digest() - SHA-256/384/512"
    echo "  • hmac() - HMAC with SHA"
    echo "  • encrypt()/decrypt() - AES"
    echo "  • pgp_sym_encrypt()/pgp_sym_decrypt() - AES"
    echo ""
    exit 0
else
    echo "=========================================="
    echo "✗ FUNCTION REMOVAL FAILED: $ERRORS errors"
    echo "=========================================="
    exit 1
fi
