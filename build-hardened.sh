#!/bin/bash

################################################################################
# Build Script for FIPS-Enabled Ubuntu PostgreSQL (STIG/CIS Hardened)
################################################################################

set -e

# Default values
IMAGE_TAG="postgresql:17.7.0-ubuntu-22.04-fips"
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
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --tag, -t <name>     Docker image tag"
            echo "  --no-cache           Build without using cache"
            echo "  --help, -h           Show this help message"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

################################################################################
# Pre-flight checks
################################################################################

echo "========================================"
echo "PostgreSQL FIPS + STIG/CIS Builder"
echo "========================================"
echo ""

if ! command -v docker &> /dev/null; then
    echo -e "${RED}✗ ERROR: Docker is not installed${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} Docker found: $(docker --version)"

if ! docker buildx version &> /dev/null; then
    echo -e "${RED}✗ ERROR: Docker BuildKit not available${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} Docker BuildKit found"

PASSWORD_FILE="$SCRIPT_DIR/wolfssl_password.txt"
if [ ! -f "$PASSWORD_FILE" ]; then
    echo -e "${RED}✗ ERROR: wolfSSL password file not found${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} wolfSSL password file found"

# Check for required build files
REQUIRED_FILES=(
    "Dockerfile.hardened"
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

if [ ! -d "$SCRIPT_DIR/rootfs" ]; then
    echo -e "${RED}✗ ERROR: Required directory missing: rootfs/${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} rootfs/"

if [ ! -d "$SCRIPT_DIR/prebuildfs" ]; then
    echo -e "${RED}✗ ERROR: Required directory missing: prebuildfs/${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} prebuildfs/"

################################################################################
# Build Docker image
################################################################################

echo ""
echo "========================================"
echo "Building Hardened Docker Image"
echo "========================================"
echo ""
echo "Image tag: $IMAGE_TAG"
echo "Dockerfile: Dockerfile.hardened"
echo "Security: FIPS 140-3 + DISA STIG + CIS"
echo ""

cd "$SCRIPT_DIR"
export DOCKER_BUILDKIT=1

echo "Starting build (25-35 minutes)..."
echo ""

if docker buildx build \
    --secret id=wolfssl_password,src="$PASSWORD_FILE" \
    --tag "$IMAGE_TAG" \
    --platform linux/amd64 \
    --file Dockerfile.hardened \
    $BUILD_ARGS \
    . ; then

    echo ""
    echo "========================================"
    echo -e "${GREEN}✓ BUILD SUCCESSFUL${NC}"
    echo "========================================"
    echo ""
    echo "Image: $IMAGE_TAG"
    echo "Security: FIPS 140-3 + DISA STIG + CIS"
    echo ""
    echo "Next steps:"
    echo "  1. Run container: docker run -d --name pg-test -e POSTGRES_PASSWORD=test123 $IMAGE_TAG"
    echo "  2. Verify FIPS: docker exec pg-test /usr/local/bin/fips-startup-check"
    echo "  3. Run compliance scan: ./scan-internal.sh $IMAGE_TAG"
    echo "  4. Stop container: docker stop pg-test && docker rm pg-test"
    echo ""
else
    echo ""
    echo "========================================"
    echo -e "${RED}✗ BUILD FAILED${NC}"
    echo "========================================"
    exit 1
fi
