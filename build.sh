#!/bin/bash

################################################################################
# Build Script for FIPS-Enabled Ubuntu PostgreSQL Docker Image
#
# This script builds the PostgreSQL FIPS container using Docker BuildKit with
# secure password handling for wolfSSL commercial FIPS package.
#
# Usage:
#   ./build.sh [OPTIONS]
#
# Options:
#   --tag, -t <name>     Docker image tag (default: postgresql-fips-ubuntu:17.6)
#   --no-cache           Build without using cache
#   --help, -h           Show this help message
#
# Requirements:
#   - Docker with BuildKit support
#   - wolfssl_password.txt file containing the wolfSSL FIPS package password
#
################################################################################

set -e

# Default values
IMAGE_TAG="postgresql-fips-ubuntu:17.6"
BUILD_ARGS=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --tag|-t)
            IMAGE_TAG="$2"
            shift 2
            ;;
        --no-cache)
            BUILD_ARGS="$BUILD_ARGS --no-cache"
            shift
            ;;
        --help|-h)
            grep '^#' "$0" | grep -v '#!/bin/bash' | sed 's/^# //' | sed 's/^#//'
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

################################################################################
# Pre-flight checks
################################################################################

echo "========================================"
echo "FIPS-Enabled Ubuntu PostgreSQL Builder"
echo "========================================"
echo ""

# Check if Docker is available
if ! command -v docker &> /dev/null; then
    echo -e "${RED}✗ ERROR: Docker is not installed or not in PATH${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} Docker found: $(docker --version)"

# Check if BuildKit is available
if ! docker buildx version &> /dev/null; then
    echo -e "${RED}✗ ERROR: Docker BuildKit (buildx) is not available${NC}"
    echo "  Please install Docker with BuildKit support"
    exit 1
fi
echo -e "${GREEN}✓${NC} Docker BuildKit found: $(docker buildx version | head -n1)"

# Check for wolfSSL password file
PASSWORD_FILE="$SCRIPT_DIR/wolfssl_password.txt"
if [ ! -f "$PASSWORD_FILE" ]; then
    echo -e "${RED}✗ ERROR: wolfSSL password file not found: $PASSWORD_FILE${NC}"
    echo ""
    echo "Please create wolfssl_password.txt with your wolfSSL FIPS package password:"
    echo "  echo 'your-password-here' > wolfssl_password.txt"
    echo "  chmod 600 wolfssl_password.txt"
    exit 1
fi
echo -e "${GREEN}✓${NC} wolfSSL password file found"

# Verify password file permissions (should not be world-readable)
PERMS=$(stat -c "%a" "$PASSWORD_FILE" 2>/dev/null || stat -f "%Lp" "$PASSWORD_FILE" 2>/dev/null)
if [[ "$PERMS" =~ [0-9][0-9][4-7] ]]; then
    echo -e "${YELLOW}⚠ WARNING: Password file is world-readable (permissions: $PERMS)${NC}"
    echo "  Recommend: chmod 600 $PASSWORD_FILE"
fi

# Check for required build files
echo ""
echo "Checking required build files..."
REQUIRED_FILES=(
    "Dockerfile"
    "fips-entrypoint.sh"
    "openssl-wolfprov.cnf"
    "test-fips.c"
    "fips-startup-check.c"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$SCRIPT_DIR/$file" ]; then
        echo -e "${RED}✗ ERROR: Required file missing: $file${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓${NC} $file"
done

# Check for Bitnami rootfs
if [ ! -d "$SCRIPT_DIR/rootfs" ]; then
    echo -e "${RED}✗ ERROR: Required directory missing: rootfs/${NC}"
    echo "  The Bitnami rootfs directory is required for scripts"
    exit 1
fi
echo -e "${GREEN}✓${NC} rootfs/"

if [ ! -d "$SCRIPT_DIR/prebuildfs" ]; then
    echo -e "${RED}✗ ERROR: Required directory missing: prebuildfs/${NC}"
    echo "  The Bitnami prebuildfs directory is required"
    exit 1
fi
echo -e "${GREEN}✓${NC} prebuildfs/"

################################################################################
# Build Docker image
################################################################################

echo ""
echo "========================================"
echo "Building Docker Image"
echo "========================================"
echo ""
echo "Image tag: $IMAGE_TAG"
echo "Build context: $SCRIPT_DIR"
echo "Build arguments: $BUILD_ARGS"
echo ""

cd "$SCRIPT_DIR"

# Enable Docker BuildKit
export DOCKER_BUILDKIT=1

# Build with secret mount for wolfSSL password
echo "Starting build (this may take 25-35 minutes on first build)..."
echo ""

if docker buildx build \
    --secret id=wolfssl_password,src="$PASSWORD_FILE" \
    --tag "$IMAGE_TAG" \
    --platform linux/amd64 \
    $BUILD_ARGS \
    . ; then

    echo ""
    echo "========================================"
    echo -e "${GREEN}✓ BUILD SUCCESSFUL${NC}"
    echo "========================================"
    echo ""
    echo "Image: $IMAGE_TAG"
    echo ""
    echo "Next steps:"
    echo "  1. Test the image:"
    echo "     docker run --rm -e POSTGRES_PASSWORD=test123 $IMAGE_TAG"
    echo ""
    echo "  2. Run with docker-compose:"
    echo "     docker-compose up -d"
    echo ""
    echo "  3. Verify FIPS mode:"
    echo "     docker exec <container> /usr/local/bin/test-provider.sh"
    echo ""
else
    echo ""
    echo "========================================"
    echo -e "${RED}✗ BUILD FAILED${NC}"
    echo "========================================"
    exit 1
fi
