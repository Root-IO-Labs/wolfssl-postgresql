#!/bin/bash
################################################################################
# Rebuild PostgreSQL FIPS Image with Latest Changes
#
# This script rebuilds the image with all FIPS compliance improvements
################################################################################

set -e

IMAGE_TAG="postgresql-fips-ubuntu:17.6.0"
BUILD_DIR="postgresql/17.6.0-ubuntu-24.04"

echo "========================================"
echo "PostgreSQL FIPS Image Rebuild"
echo "========================================"
echo "Image Tag: $IMAGE_TAG"
echo "Build Dir: $BUILD_DIR"
echo ""

# Check we're in the right directory
if [ ! -f "$BUILD_DIR/Dockerfile" ]; then
    echo "✗ ERROR: Dockerfile not found at $BUILD_DIR/Dockerfile"
    exit 1
fi

cd "$BUILD_DIR"

# Check for wolfSSL password file
if [ ! -f "wolfssl_password.txt" ]; then
    echo "✗ ERROR: wolfssl_password.txt not found"
    echo ""
    echo "Please create this file with your wolfSSL FIPS package password:"
    echo "  echo 'YOUR_PASSWORD' > wolfssl_password.txt"
    echo "  chmod 600 wolfssl_password.txt"
    exit 1
fi

echo "✓ Prerequisites check passed"
echo ""

# Clean up old image (optional)
echo "Checking for existing image..."
if docker images "$IMAGE_TAG" --format "{{.Repository}}:{{.Tag}}" | grep -q "$IMAGE_TAG"; then
    read -p "Remove existing image $IMAGE_TAG? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Removing old image..."
        docker rmi "$IMAGE_TAG" || true
    fi
fi

echo ""
echo "========================================"
echo "Starting Build"
echo "========================================"
echo "This will take 8-20 minutes depending on your hardware."
echo ""
echo "Build configuration:"
echo "  - Base: Ubuntu 22.04"
echo "  - OpenSSL: 3.0.15 (FIPS-enabled)"
echo "  - wolfSSL: 5.8.2 FIPS v5.2.3"
echo "  - wolfProvider: v1.1.0"
echo "  - PostgreSQL: 17.6"
echo ""
echo "IMPORTANT: libssl3 will NOT be installed (FIPS-only)"
echo ""

# Enable BuildKit
export DOCKER_BUILDKIT=1

# Build with progress output
echo "Building image..."
echo ""

time docker buildx build \
  --secret id=wolfssl_password,src=wolfssl_password.txt \
  --tag "$IMAGE_TAG" \
  --progress=plain \
  --file Dockerfile \
  . 2>&1 | tee "build-$(date +%Y%m%d-%H%M%S).log"

BUILD_STATUS=$?

if [ $BUILD_STATUS -eq 0 ]; then
    echo ""
    echo "========================================"
    echo "✓ BUILD SUCCESSFUL"
    echo "========================================"
    echo ""
    echo "Image: $IMAGE_TAG"
    echo "Size: $(docker images $IMAGE_TAG --format '{{.Size}}')"
    echo ""
    echo "Next steps:"
    echo "  1. Test the image:"
    echo "     docker run --rm $IMAGE_TAG /usr/local/bin/fips-startup-check"
    echo ""
    echo "  2. Run automated tests:"
    echo "     ./tests/quick-test.sh $IMAGE_TAG"
    echo ""
    echo "  3. Check for system OpenSSL (should be empty):"
    echo "     docker run --rm $IMAGE_TAG find /usr/lib /lib -name 'libssl.so*' 2>/dev/null"
    echo ""
else
    echo ""
    echo "========================================"
    echo "✗ BUILD FAILED"
    echo "========================================"
    echo ""
    echo "Check the build log above for errors."
    echo "Common issues:"
    echo "  - wolfSSL password incorrect"
    echo "  - Network connectivity issues"
    echo "  - Disk space insufficient"
    echo ""
    exit 1
fi
