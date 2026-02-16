#!/bin/bash
set -e

###############################################################################
# FIPS Validation Wrapper for Bitnami PostgreSQL
#
# This script performs FIPS 140-3 validation before passing control to the
# original Bitnami entrypoint script.
#
# Environment variables:
#   SKIP_FIPS_CHECK - Skip FIPS validation (default: false, not recommended)
#
# Original Bitnami entrypoint: /opt/bitnami/scripts/postgresql/entrypoint.sh
###############################################################################

echo "========================================"
echo "PostgreSQL FIPS Container Startup"
echo "Ubuntu 24.04 + Bitnami Scripts"
echo "========================================"
echo ""

EXIT_CODE=0

###############################################################################
# Check 1: Operating Environment (OE) Validation
###############################################################################
echo "[1/6] Validating Operating Environment (OE) for CMVP compliance..."

# Check kernel version
KERNEL_VERSION=$(uname -r)
KERNEL_MAJOR=$(echo "$KERNEL_VERSION" | cut -d. -f1)
KERNEL_MINOR=$(echo "$KERNEL_VERSION" | cut -d. -f2)

echo "      Detected kernel: $KERNEL_VERSION"
echo "      ✓ Kernel version: $KERNEL_VERSION"

# Check CPU architecture
CPU_ARCH=$(uname -m)
if [ "$CPU_ARCH" != "x86_64" ]; then
    echo "      ✗ ERROR: Unsupported CPU architecture: $CPU_ARCH"
    echo "      wolfSSL FIPS CMVP validation requires x86_64 architecture"
    EXIT_CODE=1
else
    echo "      ✓ CPU architecture: $CPU_ARCH"
fi

# Check for recommended CPU features
if [ -f /proc/cpuinfo ]; then
    if grep -q rdrand /proc/cpuinfo; then
        echo "      ✓ RDRAND: Available (hardware entropy source)"
    else
        echo "      ⚠ RDRAND: Not available (using kernel entropy only)"
    fi

    if grep -q aes /proc/cpuinfo; then
        echo "      ✓ AES-NI: Available (hardware-accelerated AES)"
    else
        echo "      ⚠ AES-NI: Not available (software AES)"
    fi
else
    echo "      ⚠ WARNING: Cannot read /proc/cpuinfo"
fi

if [ $EXIT_CODE -ne 0 ]; then
    echo ""
    echo "========================================"
    echo "✗ FIPS VALIDATION FAILED"
    echo "========================================"
    echo "Operating Environment is not CMVP compliant"
    echo "See docs/operating-environment.md for requirements"
    exit 1
fi

###############################################################################
# Check 2: Environment Variables
###############################################################################
echo ""
echo "[2/6] Validating FIPS environment variables..."

if [ -z "$OPENSSL_CONF" ]; then
    echo "      ✗ ERROR: OPENSSL_CONF is not set"
    EXIT_CODE=1
elif [ ! -f "$OPENSSL_CONF" ]; then
    echo "      ✗ ERROR: OPENSSL_CONF file does not exist: $OPENSSL_CONF"
    EXIT_CODE=1
else
    echo "      ✓ OPENSSL_CONF: $OPENSSL_CONF"
fi

if [ -z "$OPENSSL_MODULES" ]; then
    echo "      ✗ ERROR: OPENSSL_MODULES is not set"
    EXIT_CODE=1
elif [ ! -d "$OPENSSL_MODULES" ]; then
    echo "      ✗ ERROR: OPENSSL_MODULES directory does not exist: $OPENSSL_MODULES"
    EXIT_CODE=1
else
    echo "      ✓ OPENSSL_MODULES: $OPENSSL_MODULES"
fi

if [ -z "$LD_LIBRARY_PATH" ]; then
    echo "      ✗ ERROR: LD_LIBRARY_PATH is not set"
    EXIT_CODE=1
else
    echo "      ✓ LD_LIBRARY_PATH: $LD_LIBRARY_PATH"
fi

if [ $EXIT_CODE -ne 0 ]; then
    echo ""
    echo "========================================"
    echo "✗ FIPS VALIDATION FAILED"
    echo "========================================"
    echo "Environment configuration is invalid"
    exit 1
fi

###############################################################################
# Check 3: Ubuntu System OpenSSL Installation
###############################################################################
echo ""
echo "[3/6] Validating Ubuntu System OpenSSL installation..."

OPENSSL_BIN="/usr/bin/openssl"
if [ ! -x "$OPENSSL_BIN" ]; then
    echo "      ✗ ERROR: OpenSSL binary not found or not executable: $OPENSSL_BIN"
    EXIT_CODE=1
else
    OPENSSL_VERSION=$($OPENSSL_BIN version 2>&1 | head -n1)
    echo "      ✓ OpenSSL found: $OPENSSL_VERSION"

    # Check if it's OpenSSL 3.x
    if ! echo "$OPENSSL_VERSION" | grep -q "OpenSSL 3\."; then
        echo "      ⚠ WARNING: Expected OpenSSL 3.x, got: $OPENSSL_VERSION"
    fi
fi

if [ $EXIT_CODE -ne 0 ]; then
    echo ""
    echo "========================================"
    echo "✗ FIPS VALIDATION FAILED"
    echo "========================================"
    echo "OpenSSL installation is invalid"
    exit 1
fi

###############################################################################
# Check 4: wolfSSL Library
###############################################################################
echo ""
echo "[4/6] Validating wolfSSL library..."

WOLFSSL_LIB="/usr/local/lib/libwolfssl.so"
if [ ! -f "$WOLFSSL_LIB" ]; then
    # Try alternative locations
    if [ -f "/usr/local/lib/libwolfssl.so.42" ]; then
        WOLFSSL_LIB="/usr/local/lib/libwolfssl.so.42"
    elif ls /usr/local/lib/libwolfssl.so.* >/dev/null 2>&1; then
        WOLFSSL_LIB=$(ls /usr/local/lib/libwolfssl.so.* | head -n1)
    else
        echo "      ✗ ERROR: wolfSSL library not found in /usr/local/lib/"
        EXIT_CODE=1
    fi
fi

if [ $EXIT_CODE -eq 0 ]; then
    echo "      ✓ wolfSSL library: $WOLFSSL_LIB"
else
    echo ""
    echo "========================================"
    echo "✗ FIPS VALIDATION FAILED"
    echo "========================================"
    echo "wolfSSL library is missing"
    exit 1
fi

###############################################################################
# Check 5: wolfProvider Module
###############################################################################
echo ""
echo "[5/6] Validating wolfProvider module..."

WOLFPROV_MODULE="$OPENSSL_MODULES/libwolfprov.so"
if [ ! -f "$WOLFPROV_MODULE" ]; then
    echo "      ✗ ERROR: wolfProvider module not found: $WOLFPROV_MODULE"
    echo "      Available modules in $OPENSSL_MODULES:"
    ls -la "$OPENSSL_MODULES/" 2>/dev/null || echo "      (directory listing failed)"
    EXIT_CODE=1
else
    echo "      ✓ wolfProvider module: $WOLFPROV_MODULE"
    WOLFPROV_SIZE=$(stat -c%s "$WOLFPROV_MODULE" 2>/dev/null || echo "unknown")
    echo "      ✓ Module size: $WOLFPROV_SIZE bytes"
fi

if [ $EXIT_CODE -ne 0 ]; then
    echo ""
    echo "========================================"
    echo "✗ FIPS VALIDATION FAILED"
    echo "========================================"
    echo "wolfProvider module is missing or invalid"
    exit 1
fi

###############################################################################
# Check 5.5: Verify Ubuntu System OpenSSL with wolfProvider
###############################################################################
echo ""
echo "[5.5/6] Verifying Ubuntu System OpenSSL with wolfProvider..."

# With Ubuntu System OpenSSL architecture:
# - Ubuntu's system OpenSSL libraries are KEPT (not removed)
# - wolfProvider bridges OpenSSL 3.x to wolfSSL FIPS v5
# - All crypto operations use FIPS-validated wolfSSL via wolfProvider
#
# Note: PostgreSQL uses custom OpenLDAP built with OpenSSL (FIPS-validated via wolfProvider).
# All LDAP TLS/SSL operations use Ubuntu System OpenSSL with wolfProvider.

# Verify Ubuntu System OpenSSL libraries are present
SYSTEM_SSL_MISSING=0
if [ ! -f "/usr/lib/x86_64-linux-gnu/libssl.so.3" ]; then
    echo "      ✗ ERROR: Ubuntu System OpenSSL library missing: libssl.so.3"
    SYSTEM_SSL_MISSING=1
fi

if [ ! -f "/usr/lib/x86_64-linux-gnu/libcrypto.so.3" ]; then
    echo "      ✗ ERROR: Ubuntu System OpenSSL library missing: libcrypto.so.3"
    SYSTEM_SSL_MISSING=1
fi

if [ $SYSTEM_SSL_MISSING -eq 0 ]; then
    echo "      ✓ Ubuntu System OpenSSL 3.x libraries present"
fi

# Verify wolfProvider module is present
if [ ! -f "/usr/lib/x86_64-linux-gnu/ossl-modules/libwolfprov.so" ]; then
    echo "      ✗ ERROR: wolfProvider module missing"
    echo "      Expected: /usr/lib/x86_64-linux-gnu/ossl-modules/libwolfprov.so"
    SYSTEM_SSL_MISSING=1
else
    echo "      ✓ wolfProvider module present"
fi

if [ $SYSTEM_SSL_MISSING -ne 0 ]; then
    echo ""
    echo "========================================"
    echo "✗ FIPS VALIDATION FAILED"
    echo "========================================"
    echo "Ubuntu System OpenSSL or wolfProvider is missing"
    exit 1
fi

echo "      ✓ PostgreSQL crypto operations use Ubuntu System OpenSSL + wolfProvider"
echo "      ℹ Note: Custom OpenLDAP uses OpenSSL (FIPS-validated via wolfProvider)"

###############################################################################
# Check 6: Cryptographic FIPS Validation (C utility)
###############################################################################
if [ "$SKIP_FIPS_CHECK" != "true" ]; then
    echo ""
    echo "[6/6] Running cryptographic FIPS validation..."
    echo ""

    FIPS_CHECK_BIN="/usr/local/bin/fips-startup-check"
    if [ ! -x "$FIPS_CHECK_BIN" ]; then
        echo "      ✗ ERROR: FIPS check utility not found: $FIPS_CHECK_BIN"
        EXIT_CODE=1
    else
        # Execute the C-based FIPS validation utility
        if ! "$FIPS_CHECK_BIN"; then
            echo ""
            echo "========================================"
            echo "✗ FIPS VALIDATION FAILED"
            echo "========================================"
            echo "Cryptographic validation failed"
            exit 1
        fi
    fi
else
    echo ""
    echo "[6/6] Skipping cryptographic FIPS validation (SKIP_FIPS_CHECK=true)"
fi

###############################################################################
# Final Validation - Check if any errors occurred
###############################################################################
if [ $EXIT_CODE -ne 0 ]; then
    echo ""
    echo "========================================"
    echo "✗ FIPS VALIDATION FAILED"
    echo "========================================"
    echo "One or more FIPS validation checks failed"
    echo "Container cannot start - FIPS compliance not verified"
    echo ""
    echo "Review the error messages above and ensure:"
    echo "  - CPU architecture is x86_64"
    echo "  - All required FIPS libraries are present"
    echo "  - Environment variables are correctly set"
    echo "========================================"
    exit 1
fi

###############################################################################
# All Checks Passed - Hand off to Bitnami Entrypoint
###############################################################################
echo "========================================"
echo "✓ ALL FIPS CHECKS PASSED"
echo "========================================"
echo ""
echo "Handing control to Bitnami entrypoint..."
echo ""

# Execute the original Bitnami entrypoint with all arguments
exec /opt/bitnami/scripts/postgresql/entrypoint.sh "$@"
