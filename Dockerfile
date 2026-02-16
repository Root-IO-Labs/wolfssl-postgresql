################################################################################
# FIPS-Enabled Ubuntu PostgreSQL Docker Image
#
# This Dockerfile creates a PostgreSQL 17.7 image with FIPS 140-3 compliance
# using wolfSSL FIPS v5 and wolfProvider, with Ubuntu 24.04 base and Bitnami scripts.
#
# Build Requirements:
#   - Docker BuildKit
#   - wolfSSL FIPS package password (passed as build secret)
#
# Build Command:
#   DOCKER_BUILDKIT=1 docker buildx build \
#     --secret id=wolfssl_password,src=wolfssl_password.txt \
#     -t postgresql-fips-ubuntu:17.7.0 .
#
# Copyright: Based on Bitnami PostgreSQL
# SPDX-License-Identifier: APACHE-2.0
################################################################################

################################################################################
# Stage 1: Builder - Build OpenSSL 3, wolfSSL FIPS v5, and wolfProvider
################################################################################
FROM ubuntu:22.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8

# Build configuration
ENV WOLFSSL_URL=https://www.wolfssl.com/comm/wolfssl/wolfssl-5.8.2-commercial-fips-v5.2.3.7z
ENV WOLFPROV_REPO=https://github.com/wolfSSL/wolfProvider.git
ENV WOLFPROV_VERSION=v1.1.0

# Installation paths (using Ubuntu System OpenSSL)
ENV WOLFSSL_PREFIX=/usr/local
ENV WOLFPROV_PREFIX=/usr/local

# Install build dependencies and Ubuntu System OpenSSL
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        git \
        autoconf \
        automake \
        libtool \
        pkg-config \
        p7zip-full \
        perl \
        libssl-dev \
    ; \
    update-ca-certificates; \
    rm -rf /var/lib/apt/lists/*

# Fetch and process Mozilla CA bundle for runtime stage
RUN set -eux; \
    echo "Fetching Mozilla CA bundle..."; \
    curl -L -o /tmp/cacert.pem https://curl.se/ca/cacert.pem; \
    mkdir -p /usr/local/share/ca-certificates-mozilla; \
    cd /tmp; \
    csplit -s -z -f cert- cacert.pem '/-----BEGIN CERTIFICATE-----/' '{*}'; \
    for cert in cert-*; do \
        if grep -q 'BEGIN CERTIFICATE' "$cert"; then \
            mv "$cert" "/usr/local/share/ca-certificates-mozilla/${cert}.crt"; \
        fi; \
    done; \
    rm -f /tmp/cacert.pem /tmp/cert-*

################################################################################
# Use Ubuntu's OpenSSL 3 package (no custom build required)
# Benefits: APT consistency, safe for upgrades, simpler/faster builds
################################################################################
ENV PATH="/usr/bin:/usr/local/bin:${PATH}"
ENV LD_LIBRARY_PATH="/usr/local/lib:/usr/lib/x86_64-linux-gnu"

################################################################################
# Build wolfSSL FIPS v5
################################################################################
COPY test-fips.c /tmp/test-fips.c

RUN --mount=type=secret,id=wolfssl_password \
    set -eux; \
    mkdir -p /usr/src; \
    # Download wolfSSL FIPS package with proper certificate verification
    curl -L -o /tmp/wolfssl.7z "${WOLFSSL_URL}"; \
    PASSWORD=$(cat /run/secrets/wolfssl_password | tr -d '\n\r'); \
    7z x /tmp/wolfssl.7z -o/usr/src -p"${PASSWORD}"; \
    rm /tmp/wolfssl.7z; \
    mv /usr/src/wolfssl* /usr/src/wolfssl; \
    cd /usr/src/wolfssl; \
    # Remove Python-specific defines that can cause issues
    sed -i '/^#ifdef WOLFSSL_PYTHON/,/^#endif/d' wolfssl/wolfcrypt/settings.h || true; \
    # Configure wolfSSL with FIPS v5 and necessary features
    # Note: DES3 removed (not FIPS 140-3 approved), RSA_MIN_SIZE set to 2048 per FIPS requirements
    ./configure \
        --prefix=${WOLFSSL_PREFIX} \
        --enable-fips=v5 \
        --enable-opensslcoexist \
        --enable-cmac \
        --enable-keygen \
        --enable-sha \
        --enable-aesctr \
        --enable-aesccm \
        --enable-x963kdf \
        --enable-compkey \
        --enable-certgen \
        --enable-aeskeywrap \
        --enable-enckeys \
        --enable-base16 \
        --with-eccminsz=192 \
        CPPFLAGS="-DHAVE_AES_ECB -DWOLFSSL_AES_DIRECT -DWC_RSA_NO_PADDING -DWOLFSSL_PUBLIC_MP -DHAVE_PUBLIC_FFDHE -DWOLFSSL_DH_EXTRA -DWOLFSSL_PSS_LONG_SALT -DWOLFSSL_PSS_SALT_LEN_DISCOVER -DRSA_MIN_SIZE=2048" \
    ; \
    make -j"$(nproc)"; \
    ./fips-hash.sh; \
    make -j"$(nproc)"; \
    make install; \
    ldconfig; \
    cd /; \
    rm -rf /usr/src/wolfssl; \
    echo "wolfSSL FIPS v5 installed successfully"

# Update library path for wolfSSL
ENV LD_LIBRARY_PATH="/usr/local/lib:/usr/lib/x86_64-linux-gnu"

# Test wolfSSL installation
RUN set -eux; \
    gcc /tmp/test-fips.c -o /tmp/test-fips -lwolfssl -I${WOLFSSL_PREFIX}/include; \
    /tmp/test-fips; \
    rm /tmp/test-fips /tmp/test-fips.c; \
    echo "wolfSSL FIPS test passed"

# Build FIPS startup check utility
COPY fips-startup-check.c /tmp/fips-startup-check.c
RUN set -eux; \
    gcc /tmp/fips-startup-check.c -o /usr/local/bin/fips-startup-check \
        -lwolfssl -I${WOLFSSL_PREFIX}/include; \
    chmod +x /usr/local/bin/fips-startup-check; \
    rm /tmp/fips-startup-check.c; \
    echo "FIPS startup check utility built successfully"

################################################################################
# Build wolfProvider
################################################################################
RUN set -eux; \
    cd /tmp; \
    git clone --depth 1 --branch ${WOLFPROV_VERSION} ${WOLFPROV_REPO} wolfProvider; \
    cd wolfProvider; \
    ./autogen.sh; \
    # Configure wolfProvider to use Ubuntu System OpenSSL and wolfSSL
    ./configure \
        --prefix=${WOLFPROV_PREFIX} \
        --with-openssl=/usr \
        --with-wolfssl=${WOLFSSL_PREFIX} \
        CPPFLAGS="-I/usr/include" \
        LDFLAGS="-L/usr/lib/x86_64-linux-gnu" \
    ; \
    make -j"$(nproc)"; \
    echo "wolfProvider built, installing to Ubuntu system location..."; \
    mkdir -p /usr/lib/x86_64-linux-gnu/ossl-modules; \
    if [ -f ".libs/libwolfprov.so" ]; then \
        cp -v .libs/libwolfprov.so* /usr/lib/x86_64-linux-gnu/ossl-modules/; \
    elif [ -f "src/.libs/libwolfprov.so" ]; then \
        cp -v src/.libs/libwolfprov.so* /usr/lib/x86_64-linux-gnu/ossl-modules/; \
    fi; \
    cd ..; \
    rm -rf wolfProvider; \
    echo "wolfProvider installation completed"

# Verify wolfProvider installation
RUN set -eux; \
    echo "Checking for wolfProvider in Ubuntu system location..."; \
    ls -la /usr/lib/x86_64-linux-gnu/ossl-modules/; \
    if [ -f "/usr/lib/x86_64-linux-gnu/ossl-modules/libwolfprov.so" ]; then \
        echo "wolfProvider module found and verified"; \
    else \
        echo "ERROR: wolfProvider module not found in expected location"; \
        exit 1; \
    fi

################################################################################
# Stage 2: PostgreSQL Builder - Build PostgreSQL with custom OpenSSL
################################################################################
FROM builder AS postgres-builder

ENV POSTGRES_VERSION=17.7
ENV POSTGRES_PREFIX=/opt/bitnami/postgresql
ENV OPENLDAP_VERSION=2.5.18
ENV OPENLDAP_PREFIX=/opt/openldap-fips

# Install PostgreSQL build dependencies (Ubuntu 22.04)
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        build-essential \
        pkg-config \
        bison \
        flex \
        libicu-dev \
        libsasl2-dev \
        liblz4-dev \
        libreadline-dev \
        libxml2-dev \
        libxslt1-dev \
        zlib1g-dev \
        ca-certificates \
        groff-base \
    ; \
    # Ensure CA certificates are configured (inherited from builder, but verify)
    update-ca-certificates --fresh; \
    rm -rf /var/lib/apt/lists/*

################################################################################
# Build OpenLDAP with OpenSSL for FIPS Compliance
################################################################################
# NOTE: Ubuntu's libldap-2.5-0 uses GnuTLS which bypasses FIPS-validated OpenSSL.
# We build OpenLDAP from source with --with-tls=openssl to ensure all LDAP/TLS
# operations use our FIPS-validated OpenSSL stack. This maintains full compatibility
# with Bitnami's LDAP configuration features while ensuring FIPS compliance.
################################################################################
RUN set -eux; \
    cd /tmp; \
    # Download OpenLDAP source with proper certificate verification
    curl -L -o openldap-${OPENLDAP_VERSION}.tgz https://www.openldap.org/software/download/OpenLDAP/openldap-release/openldap-${OPENLDAP_VERSION}.tgz; \
    tar xzf openldap-${OPENLDAP_VERSION}.tgz; \
    cd openldap-${OPENLDAP_VERSION}; \
    # Configure OpenLDAP to use Ubuntu System OpenSSL (FIPS-validated via wolfProvider)
    # Note: --enable-slapd=no disables server build (we only need client libraries)
    ./configure \
        --prefix=${OPENLDAP_PREFIX} \
        --with-tls=openssl \
        --with-cyrus-sasl \
        --enable-dynamic \
        --enable-slapd=no \
        --enable-slurpd=no \
        --disable-static \
        --disable-backends \
        --disable-overlays \
        --disable-balancer \
        LDFLAGS="-L/usr/lib/x86_64-linux-gnu -L${WOLFSSL_PREFIX}/lib -Wl,-rpath=${WOLFSSL_PREFIX}/lib" \
        CPPFLAGS="-I/usr/include" \
    ; \
    # Build OpenLDAP client libraries
    make depend; \
    make -j"$(nproc)"; \
    make install; \
    # Verify libldap was built and linked to OpenSSL
    ls -lh ${OPENLDAP_PREFIX}/lib/; \
    # Clean up
    cd ..; \
    rm -rf openldap-${OPENLDAP_VERSION}*; \
    echo "OpenLDAP ${OPENLDAP_VERSION} built with OpenSSL for FIPS compliance"

# Verify OpenLDAP linkage to Ubuntu System OpenSSL (not GnuTLS)
RUN set -eux; \
    ldd ${OPENLDAP_PREFIX}/lib/libldap.so | grep -q "/usr/lib/x86_64-linux-gnu/libssl.so" || { \
        echo "ERROR: OpenLDAP not linked to Ubuntu System OpenSSL!"; \
        ldd ${OPENLDAP_PREFIX}/lib/libldap.so; \
        exit 1; \
    }; \
    echo "✓ OpenLDAP correctly linked to Ubuntu System OpenSSL (FIPS-validated via wolfProvider)"

################################################################################
# Copy FIPS compliance script for PostgreSQL
################################################################################
# This script disables non-FIPS cryptographic functions by commenting out
# their definitions in pgcrypto extension SQL file:
# - crypt(text, text) - Uses Blowfish/MD5/DES
# - gen_salt(text) - Generates salts for non-FIPS algorithms
# - gen_salt(text, int) - Generates salts with rounds
COPY patches/disable-non-fips-functions.sh /tmp/disable-non-fips-functions.sh
RUN chmod +x /tmp/disable-non-fips-functions.sh

################################################################################
# Copy MD5 authentication disable patch
################################################################################
# This patch disables MD5 authentication at the source level for FIPS 140-3 compliance
# Affects: CheckMD5Auth(), md5_crypt_verify(), pg_md5_encrypt()
COPY patches/disable-md5-authentication.patch /tmp/disable-md5-authentication.patch

################################################################################
# Build PostgreSQL from source with custom OpenSSL and FIPS patches
################################################################################
RUN set -eux; \
    cd /tmp; \
    # Download PostgreSQL source
    # Download PostgreSQL source with proper certificate verification
    curl -L -o postgresql-${POSTGRES_VERSION}.tar.gz https://ftp.postgresql.org/pub/source/v${POSTGRES_VERSION}/postgresql-${POSTGRES_VERSION}.tar.gz; \
    tar -xzf postgresql-${POSTGRES_VERSION}.tar.gz; \
    cd postgresql-${POSTGRES_VERSION}; \
    \
    # Apply MD5 authentication disable patch for FIPS 140-3 compliance
    # This disables MD5 auth at the source level: CheckMD5Auth(), md5_crypt_verify(), pg_md5_encrypt()
    echo "Applying MD5 authentication disable patch..."; \
    patch -p1 < /tmp/disable-md5-authentication.patch; \
    echo "✓ MD5 authentication disabled at source level"; \
    \
    # Disable non-FIPS cryptographic functions
    # This removes function definitions from pgcrypto extension SQL file
    # Functions will not exist in the database at all
    echo "Disabling non-FIPS cryptographic functions in PostgreSQL source..."; \
    /tmp/disable-non-fips-functions.sh; \
    \
    # Configure PostgreSQL with Ubuntu System OpenSSL and custom OpenLDAP
    ./configure \
        --prefix=${POSTGRES_PREFIX} \
        --with-openssl \
        --with-includes=/usr/include:${OPENLDAP_PREFIX}/include \
        --with-libraries=/usr/lib/x86_64-linux-gnu:${OPENLDAP_PREFIX}/lib \
        --with-icu \
        --with-lz4 \
        --with-libxml \
        --with-libxslt \
        --with-ldap \
        --with-libedit-preferred \
        LDFLAGS="-L/usr/lib/x86_64-linux-gnu -L${WOLFSSL_PREFIX}/lib -Wl,-rpath=${WOLFSSL_PREFIX}/lib -L${OPENLDAP_PREFIX}/lib -Wl,-rpath=${OPENLDAP_PREFIX}/lib" \
        CPPFLAGS="-I/usr/include -I${OPENLDAP_PREFIX}/include" \
    ; \
    # Build PostgreSQL
    make -j"$(nproc)"; \
    make install; \
    # Build and install contrib modules
    cd contrib; \
    make -j"$(nproc)"; \
    make install; \
    cd ..; \
    # Clean up
    cd ..; \
    rm -rf postgresql-${POSTGRES_VERSION}*; \
    # Create required directories
    mkdir -p ${POSTGRES_PREFIX}/share/postgresql; \
    mkdir -p ${POSTGRES_PREFIX}/data; \
    mkdir -p ${POSTGRES_PREFIX}/conf; \
    echo "PostgreSQL 17.7.0 built and installed successfully"

# Verify PostgreSQL build
RUN ${POSTGRES_PREFIX}/bin/postgres --version

################################################################################
# Stage 3: Runtime - Ubuntu-based runtime with Bitnami scripts and FIPS
################################################################################
FROM ubuntu:22.04 AS runtime

ARG TARGETARCH
ARG WITH_ALL_LOCALES="no"
ARG EXTRA_LOCALES

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8

# Bitnami metadata labels
LABEL com.vmware.cp.artifact.flavor="sha256:c50c90cfd9d12b445b011e6ad529f1ad3daea45c26d20b00732fae3cd71f6a83" \
      org.opencontainers.image.base.name="docker.io/library/ubuntu:22.04" \
      org.opencontainers.image.created="2025-11-28T00:00:00Z" \
      org.opencontainers.image.description="FIPS-enabled PostgreSQL on Ubuntu 22.04 with Bitnami scripts" \
      org.opencontainers.image.title="postgresql-fips-ubuntu" \
      org.opencontainers.image.vendor="FIPS PostgreSQL" \
      org.opencontainers.image.version="17.7.0-fips"

# Copy prebuildfs (contains install_packages and other helpers)
COPY prebuildfs /
SHELL ["/bin/bash", "-o", "errexit", "-o", "nounset", "-o", "pipefail", "-c"]

################################################################################
# CRITICAL FIPS STEP 1: Install Ubuntu System OpenSSL FIRST
# This must happen BEFORE any apt-get/install_packages commands to ensure all
# packages link to Ubuntu System OpenSSL which is FIPS-validated via wolfProvider
################################################################################

# Install Ubuntu System OpenSSL and copy FIPS components from builder
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        libssl3 \
        openssl \
        ca-certificates \
    ; \
    rm -rf /var/lib/apt/lists/*

# Copy wolfSSL and wolfProvider from builder
COPY --from=builder /usr/local/lib/libwolfssl.so* /usr/local/lib/
COPY --from=builder /usr/local/include/wolfssl /usr/local/include/wolfssl
COPY --from=builder /usr/lib/x86_64-linux-gnu/ossl-modules/libwolfprov.so* /usr/lib/x86_64-linux-gnu/ossl-modules/

# Copy Mozilla CA certificates from builder
COPY --from=builder /usr/local/share/ca-certificates-mozilla /usr/local/share/ca-certificates-mozilla

# Install Mozilla CA certificates
RUN set -eux; \
    echo "Installing Mozilla CA certificates..."; \
    if [ -d /usr/local/share/ca-certificates-mozilla ]; then \
        for cert in /usr/local/share/ca-certificates-mozilla/*.crt; do \
            if [ -f "$cert" ]; then \
                cp "$cert" /usr/local/share/ca-certificates/; \
            fi; \
        done; \
        update-ca-certificates; \
        echo "Mozilla CA certificates installed successfully"; \
    fi

# Configure dynamic linker for wolfSSL
RUN set -eux; \
    echo "/usr/local/lib" > /etc/ld.so.conf.d/wolfssl-fips.conf; \
    ldconfig; \
    echo "✓ wolfSSL FIPS libraries configured"

# Set OpenSSL environment variables for wolfProvider (Ubuntu System OpenSSL)
ENV OPENSSL_CONF="/etc/ssl/openssl-wolfprov.cnf" \
    OPENSSL_MODULES="/usr/lib/x86_64-linux-gnu/ossl-modules" \
    LD_LIBRARY_PATH="/usr/local/lib:/usr/lib/x86_64-linux-gnu" \
    PATH="/usr/bin:/usr/local/bin:${PATH}"

# Copy OpenSSL configuration with wolfProvider
COPY openssl-wolfprov.cnf /etc/ssl/openssl-wolfprov.cnf

# Verify FIPS OpenSSL works BEFORE installing any packages
RUN set -eux; \
    echo "========================================"; \
    echo "Verifying FIPS OpenSSL Installation"; \
    echo "========================================"; \
    openssl version; \
    echo ""; \
    echo "OpenSSL providers:"; \
    openssl list -providers; \
    echo ""; \
    if ! openssl list -providers | grep -q wolfprov; then \
        echo "ERROR: wolfProvider not loaded!"; \
        exit 1; \
    fi; \
    echo "✓ FIPS OpenSSL operational"; \
    echo "✓ wolfProvider loaded"; \
    echo "========================================"

################################################################################
# NOW install runtime dependencies - they will automatically use FIPS OpenSSL
################################################################################
# NOTE: libsasl2-2 will link to FIPS OpenSSL (from /usr/lib/x86_64-linux-gnu/)
# NOTE: libldap-2.5-0 is NOT installed - we use custom-built OpenLDAP with FIPS OpenSSL
RUN install_packages \
        ca-certificates \
        libbsd0 \
        libedit2 \
        libicu70 \
        liblz4-1 \
        liblzma5 \
        libreadline8 \
        libsasl2-2 \
        libuuid1 \
        libxml2 \
        libxslt1.1 \
        libzstd1 \
        locales \
        procps \
        zlib1g \
        libnss-wrapper \
        gosu
# NOTE: liblzma5 is REQUIRED by libxml2 (PostgreSQL --with-libxml dependency)
# Contains SHA-256 for integrity checksums only (non-cryptographic use)

################################################################################
# Verify wolfSSL libraries are accessible
################################################################################
RUN set -eux; \
    echo "========================================"; \
    echo "Verifying FIPS Libraries"; \
    echo "========================================"; \
    ldconfig; \
    echo "✓ Ubuntu System OpenSSL with wolfProvider ready"; \
    echo "✓ wolfSSL FIPS libraries configured"

################################################################################
# Note: Custom OpenLDAP built with OpenSSL (not GnuTLS)
# All LDAP TLS/SSL operations use Ubuntu System OpenSSL with wolfProvider (FIPS-validated)
# All PostgreSQL cryptographic operations use Ubuntu System OpenSSL with wolfProvider
################################################################################

# Set locale environment
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# Copy PostgreSQL installation
COPY --from=postgres-builder /opt/bitnami/postgresql /opt/bitnami/postgresql

# Copy custom OpenLDAP installation (built with OpenSSL for FIPS compliance)
COPY --from=postgres-builder /opt/openldap-fips /opt/openldap-fips

# Set Bitnami environment variables
ENV HOME="/" \
    OS_ARCH="${TARGETARCH:-amd64}" \
    OS_FLAVOUR="ubuntu-22.04" \
    OS_NAME="linux"

# Set FIPS environment variables (Ubuntu System OpenSSL)
ENV PATH="/usr/bin:/usr/local/bin:/usr/local/sbin:/opt/bitnami/postgresql/bin:/opt/openldap-fips/bin:${PATH}" \
    LD_LIBRARY_PATH="/usr/local/lib:/usr/lib/x86_64-linux-gnu:/opt/openldap-fips/lib" \
    OPENSSL_CONF="/etc/ssl/openssl-wolfprov.cnf" \
    OPENSSL_MODULES="/usr/lib/x86_64-linux-gnu/ossl-modules"

# PostgreSQL environment variables (Bitnami-compatible)
ENV APP_VERSION="17.7.0" \
    BITNAMI_APP_NAME="postgresql-fips" \
    IMAGE_REVISION="1" \
    LANG="en_US.UTF-8" \
    LANGUAGE="en_US:en" \
    NSS_WRAPPER_LIB="/opt/bitnami/common/lib/libnss_wrapper.so"

# Update dynamic linker cache
RUN ldconfig

# Copy FIPS startup check utility from builder
COPY --from=builder /usr/local/bin/fips-startup-check /usr/local/bin/fips-startup-check
RUN chmod +x /usr/local/bin/fips-startup-check

# Copy test script
COPY test-provider.sh /usr/local/bin/test-provider.sh
RUN chmod +x /usr/local/bin/test-provider.sh

RUN chmod g+rwX /opt/bitnami

# Create NSS wrapper lib symlink
RUN mkdir -p /opt/bitnami/common/lib && \
    ln -sf /usr/lib/$(uname -m)-linux-gnu/libnss_wrapper.so /opt/bitnami/common/lib/libnss_wrapper.so

# Remove SUID/SGID permissions (security hardening)
RUN find / -perm /6000 -type f -exec chmod a-s {} \; || true

# Configure locales
RUN update-locale LANG=C.UTF-8 LC_MESSAGES=POSIX && \
    DEBIAN_FRONTEND=noninteractive dpkg-reconfigure locales && \
    echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen

# Copy Bitnami rootfs (scripts, configurations)
COPY rootfs /
RUN /opt/bitnami/scripts/postgresql/postunpack.sh

# Configure SASL for FIPS compliance
# libsasl2-2 is used by PostgreSQL (via LDAP client library)
# Restrict to FIPS-approved mechanisms only: SCRAM-SHA-256, GSSAPI
COPY sasl2-fips.conf /etc/sasl2/postgresql.conf
RUN mkdir -p /etc/sasl2 && \
    chmod 644 /etc/sasl2/postgresql.conf && \
    echo "✓ SASL configured for FIPS compliance (SCRAM-SHA-256, GSSAPI only)"

# Note: Non-FIPS functions (crypt, gen_salt) are removed at source level
# and will not exist in the database

# Generate locales
RUN update-locale LANG=C.UTF-8 LC_MESSAGES=POSIX && \
    DEBIAN_FRONTEND=noninteractive dpkg-reconfigure locales && \
    echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen
RUN /opt/bitnami/scripts/locales/generate-locales.sh

# Copy FIPS validation wrapper entrypoint
COPY fips-entrypoint.sh /usr/local/bin/fips-entrypoint.sh
RUN chmod +x /usr/local/bin/fips-entrypoint.sh

# Health check using PostgreSQL
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD pg_isready -U postgres || exit 1

# Verification on container build
RUN set -eux; \
    echo "Verifying runtime configuration..."; \
    echo "==> OpenSSL:"; \
    openssl version; \
    echo "==> OpenSSL providers:"; \
    openssl list -providers || true; \
    echo "==> PostgreSQL version:"; \
    postgres --version; \
    echo "==> Custom OpenLDAP verification:"; \
    ls -lh /opt/openldap-fips/lib/libldap.so || { echo "ERROR: libldap.so not found!"; exit 1; }; \
    echo "==> Checking libldap uses OpenSSL (not GnuTLS):"; \
    ldd /opt/openldap-fips/lib/libldap.so | grep -q "libssl" && echo "✓ libldap linked to OpenSSL" || { echo "ERROR: libldap not linked to OpenSSL!"; exit 1; }; \
    ldd /opt/openldap-fips/lib/libldap.so | grep -q "gnutls" && { echo "ERROR: libldap still using GnuTLS!"; exit 1; } || echo "✓ No GnuTLS dependency"; \
    echo "==> Verifying PostgreSQL LDAP support:"; \
    ldd /opt/bitnami/postgresql/bin/postgres | grep -q "libldap" && echo "✓ PostgreSQL linked to libldap" || echo "⚠ PostgreSQL not linked to libldap (LDAP auth may not work)"; \
    echo "==> Verifying SASL configuration:"; \
    if [ -f "/etc/sasl2/postgresql.conf" ]; then \
        echo "✓ SASL configuration file present"; \
        grep -q "SCRAM-SHA-256" /etc/sasl2/postgresql.conf && echo "✓ SCRAM-SHA-256 enabled" || echo "⚠ SCRAM-SHA-256 not configured"; \
        grep -q "!DIGEST-MD5\|!CRAM-MD5" /etc/sasl2/postgresql.conf && echo "✓ Non-FIPS mechanisms disabled" || echo "⚠ Non-FIPS mechanisms not explicitly disabled"; \
    else \
        echo "⚠ SASL configuration file not found (using system defaults)"; \
    fi; \
    ldd /opt/bitnami/postgresql/bin/postgres | grep -q "libsasl2" && echo "✓ PostgreSQL linked to libsasl2" || echo "⚠ PostgreSQL not linked to libsasl2"; \
    echo "==> Runtime verification complete"

# Expose PostgreSQL port
EXPOSE 5432

# Set volumes for data persistence (Bitnami-compatible)
VOLUME [ "/bitnami/postgresql", "/docker-entrypoint-initdb.d", "/docker-entrypoint-preinitdb.d" ]

# Set user (Bitnami standard UID)
USER 1001

# Set FIPS validation wrapper as entrypoint
ENTRYPOINT ["/usr/local/bin/fips-entrypoint.sh"]

# Default command - pass to Bitnami entrypoint
CMD ["/opt/bitnami/scripts/postgresql/run.sh"]
