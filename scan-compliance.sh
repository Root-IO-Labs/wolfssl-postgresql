#!/bin/bash

################################################################################
# OpenSCAP Compliance Scanning Script for PostgreSQL Hardened Image
# Generates STIG and CIS compliance reports
################################################################################

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
IMAGE_NAME="${IMAGE_NAME:-postgresql-fips-hardened:17.6}"
REPORT_DIR="stig-cis-report"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
CONTAINER_NAME="postgresql-scan-${TIMESTAMP}"
SCAP_SECURITY_GUIDE_VERSION="0.1.73"

echo "========================================"
echo "OpenSCAP Compliance Scanner"
echo "PostgreSQL Hardened Image"
echo "========================================"
echo ""

################################################################################
# Pre-flight Checks
################################################################################

echo -e "${BLUE}[INFO]${NC} Checking prerequisites..."

# Check if Docker is available
if ! command -v docker &> /dev/null; then
    echo -e "${RED}✗ ERROR: Docker is not installed${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} Docker found"

# Check if OpenSCAP is installed on HOST
if ! command -v oscap &> /dev/null; then
    echo -e "${RED}✗ ERROR: OpenSCAP is not installed on host${NC}"
    echo ""
    echo "Please install OpenSCAP tools on your host machine:"
    echo "  sudo apt-get update"
    echo "  sudo apt-get install -y libopenscap8 openscap-scanner ssg-base ssg-debderived"
    echo ""
    exit 1
fi
echo -e "${GREEN}✓${NC} OpenSCAP found on host"

# Check if image exists
if ! docker image inspect "$IMAGE_NAME" &> /dev/null; then
    echo -e "${RED}✗ ERROR: Image not found: $IMAGE_NAME${NC}"
    echo "Please build the image first using ./build-hardened.sh"
    exit 1
fi
echo -e "${GREEN}✓${NC} Image found: $IMAGE_NAME"

# Create report directory
mkdir -p "$REPORT_DIR"
echo -e "${GREEN}✓${NC} Report directory: $REPORT_DIR"

################################################################################
# Download SCAP Security Guide
################################################################################

echo ""
echo -e "${BLUE}[INFO]${NC} Preparing SCAP Security Guide..."

SCAP_DIR="$REPORT_DIR/scap-content"
mkdir -p "$SCAP_DIR"

# Download Ubuntu 22.04 SCAP Security Guide if not present
if [ ! -f "$SCAP_DIR/ssg-ubuntu2204-ds.xml" ]; then
    echo "Downloading SCAP Security Guide v${SCAP_SECURITY_GUIDE_VERSION}..."
    
    if command -v wget &> /dev/null; then
        wget -q "https://github.com/ComplianceAsCode/content/releases/download/v${SCAP_SECURITY_GUIDE_VERSION}/scap-security-guide-${SCAP_SECURITY_GUIDE_VERSION}.zip" -O "$SCAP_DIR/ssg.zip" 2>/dev/null || {
            echo -e "${YELLOW}⚠ WARNING: Could not download SCAP Security Guide${NC}"
        }
        
        if [ -f "$SCAP_DIR/ssg.zip" ]; then
            cd "$SCAP_DIR"
            unzip -q ssg.zip "*/ssg-ubuntu2204-ds.xml" 2>/dev/null || true
            find . -name "ssg-ubuntu2204-ds.xml" -exec mv {} . \; 2>/dev/null || true
            rm -f ssg.zip
            cd - > /dev/null
        fi
    fi
fi

if [ -f "$SCAP_DIR/ssg-ubuntu2204-ds.xml" ]; then
    echo -e "${GREEN}✓${NC} SCAP Security Guide ready"
    USE_SCAP=true
else
    echo -e "${YELLOW}⚠ WARNING: SCAP content not available, will perform basic compliance checks${NC}"
    USE_SCAP=false
fi

################################################################################
# Start Container for Scanning
################################################################################

echo ""
echo -e "${BLUE}[INFO]${NC} Starting container for scanning..."

# Start container in detached mode
docker run -d --name "$CONTAINER_NAME" \
    -e POSTGRES_PASSWORD=scantest123 \
    "$IMAGE_NAME" > /dev/null

echo -e "${GREEN}✓${NC} Container started: $CONTAINER_NAME"

# Wait for container to be ready
sleep 5

################################################################################
# Get Container PID for Host-Based Scanning
################################################################################

echo ""
echo -e "${BLUE}[INFO]${NC} Preparing for host-based OpenSCAP scanning..."

# Get container PID
CONTAINER_PID=$(docker inspect --format '{{.State.Pid}}' "$CONTAINER_NAME")
if [ -z "$CONTAINER_PID" ] || [ "$CONTAINER_PID" = "0" ]; then
    echo -e "${RED}✗ ERROR: Could not get container PID${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} Container PID: $CONTAINER_PID"

# Set OpenSCAP to scan container filesystem from host
export OSCAP_PROBE_ROOT="/proc/${CONTAINER_PID}/root"
echo -e "${GREEN}✓${NC} OpenSCAP probe root: $OSCAP_PROBE_ROOT"

################################################################################
# Run Compliance Scans
################################################################################

echo ""
echo "========================================"
echo "Running Compliance Scans"
echo "========================================"
echo ""

# Basic security checks report
BASIC_REPORT="$REPORT_DIR/postgresql-basic-security-${TIMESTAMP}.txt"

echo -e "${BLUE}[INFO]${NC} Running basic security checks..."

cat > "$BASIC_REPORT" << 'REPORT_HEADER'
================================================================================
PostgreSQL Hardened Image - Security Compliance Report
================================================================================

REPORT_HEADER

echo "Scan Date: $(date)" >> "$BASIC_REPORT"
echo "Image: $IMAGE_NAME" >> "$BASIC_REPORT"
echo "" >> "$BASIC_REPORT"

# Check FIPS mode
echo "=== FIPS Validation ===" >> "$BASIC_REPORT"
docker exec "$CONTAINER_NAME" bash -c '
if [ -f /usr/local/bin/fips-startup-check ]; then
    /usr/local/bin/fips-startup-check 2>&1 || echo "FIPS check available"
else
    echo "FIPS startup check not found"
fi
' >> "$BASIC_REPORT" 2>&1

echo "" >> "$BASIC_REPORT"

# Check file permissions
echo "=== Critical File Permissions ===" >> "$BASIC_REPORT"
docker exec "$CONTAINER_NAME" bash -c '
echo "Checking /etc/passwd permissions:"
ls -la /etc/passwd | awk "{print \$1, \$3, \$4, \$9}"
echo "Checking /etc/shadow permissions:"
ls -la /etc/shadow 2>/dev/null | awk "{print \$1, \$3, \$4, \$9}" || echo "N/A (container environment)"
echo "Checking /etc/group permissions:"
ls -la /etc/group | awk "{print \$1, \$3, \$4, \$9}"
' >> "$BASIC_REPORT" 2>&1

echo "" >> "$BASIC_REPORT"

# Check password policy
echo "=== Password Policy (from /etc/login.defs) ===" >> "$BASIC_REPORT"
docker exec "$CONTAINER_NAME" bash -c '
grep -E "^PASS_MAX_DAYS|^PASS_MIN_DAYS|^PASS_WARN_AGE" /etc/login.defs 2>/dev/null || echo "N/A"
' >> "$BASIC_REPORT" 2>&1

echo "" >> "$BASIC_REPORT"

# Check installed packages
echo "=== Security-Related Packages ===" >> "$BASIC_REPORT"
docker exec "$CONTAINER_NAME" bash -c '
dpkg -l | grep -E "aide|auditd|rsyslog|libpam-pwquality" | awk "{print \$2, \$3}"
' >> "$BASIC_REPORT" 2>&1

echo "" >> "$BASIC_REPORT"

# Check kernel parameters
echo "=== Kernel Security Parameters ===" >> "$BASIC_REPORT"
docker exec "$CONTAINER_NAME" bash -c '
if [ -f /etc/sysctl.d/99-stig-hardening.conf ]; then
    cat /etc/sysctl.d/99-stig-hardening.conf | head -20
else
    echo "STIG hardening config not found"
fi
' >> "$BASIC_REPORT" 2>&1

echo "" >> "$BASIC_REPORT"

# Check audit rules
echo "=== Audit Rules ===" >> "$BASIC_REPORT"
docker exec "$CONTAINER_NAME" bash -c '
if [ -f /etc/audit/rules.d/stig.rules ]; then
    cat /etc/audit/rules.d/stig.rules | grep -v "^#" | grep -v "^$"
else
    echo "STIG audit rules not found"
fi
' >> "$BASIC_REPORT" 2>&1

echo "" >> "$BASIC_REPORT"

# Check SSH configuration
echo "=== SSH Hardening Configuration ===" >> "$BASIC_REPORT"
docker exec "$CONTAINER_NAME" bash -c '
if [ -f /etc/ssh/sshd_config.d/99-stig-hardening.conf ]; then
    cat /etc/ssh/sshd_config.d/99-stig-hardening.conf
else
    echo "SSH STIG hardening config not found"
fi
' >> "$BASIC_REPORT" 2>&1

echo "" >> "$BASIC_REPORT"
echo "=== End of Basic Security Report ===" >> "$BASIC_REPORT"

echo -e "${GREEN}✓${NC} Basic security report: $BASIC_REPORT"

# Run OpenSCAP scan if available
if [ "$USE_SCAP" = true ]; then
    echo ""
    echo -e "${BLUE}[INFO]${NC} Running OpenSCAP STIG/CIS scans from host..."
    
    # Run STIG profile scan from HOST
    STIG_REPORT_HTML="$REPORT_DIR/postgresql-stig-${TIMESTAMP}.html"
    STIG_REPORT_XML="$REPORT_DIR/postgresql-stig-${TIMESTAMP}.xml"
    
    echo -e "${YELLOW}Running DISA STIG scan...${NC}"
    sudo -E oscap xccdf eval \
        --profile xccdf_org.ssgproject.content_profile_stig \
        --results "$STIG_REPORT_XML" \
        --report "$STIG_REPORT_HTML" \
        "$SCAP_DIR/ssg-ubuntu2204-ds.xml" > /dev/null 2>&1 || true
    
    if [ -f "$STIG_REPORT_HTML" ]; then
        REPORT_SIZE=$(ls -lh "$STIG_REPORT_HTML" | awk '{print $5}')
        echo -e "${GREEN}✓${NC} STIG HTML report: $STIG_REPORT_HTML (${REPORT_SIZE})"
    fi
    if [ -f "$STIG_REPORT_XML" ]; then
        echo -e "${GREEN}✓${NC} STIG XML report: $STIG_REPORT_XML"
        
        # Parse results
        STIG_PASS=$(grep -c '<result>pass</result>' "$STIG_REPORT_XML" 2>/dev/null || echo "0")
        STIG_FAIL=$(grep -c '<result>fail</result>' "$STIG_REPORT_XML" 2>/dev/null || echo "0")
        TOTAL=$((STIG_PASS + STIG_FAIL))
        if [ $TOTAL -gt 0 ]; then
            COMPLIANCE=$(awk "BEGIN {printf \"%.1f\", ($STIG_PASS / $TOTAL) * 100}")
            echo -e "${BLUE}  STIG Compliance: ${COMPLIANCE}% (${STIG_PASS} pass / ${STIG_FAIL} fail)${NC}"
        fi
    fi
    
    echo ""
    
    # Run CIS profile scan from HOST
    CIS_REPORT_HTML="$REPORT_DIR/postgresql-cis-${TIMESTAMP}.html"
    CIS_REPORT_XML="$REPORT_DIR/postgresql-cis-${TIMESTAMP}.xml"
    
    echo -e "${YELLOW}Running CIS Benchmark scan...${NC}"
    sudo -E oscap xccdf eval \
        --profile xccdf_org.ssgproject.content_profile_cis_level1_server \
        --results "$CIS_REPORT_XML" \
        --report "$CIS_REPORT_HTML" \
        "$SCAP_DIR/ssg-ubuntu2204-ds.xml" > /dev/null 2>&1 || true
    
    if [ -f "$CIS_REPORT_HTML" ]; then
        REPORT_SIZE=$(ls -lh "$CIS_REPORT_HTML" | awk '{print $5}')
        echo -e "${GREEN}✓${NC} CIS HTML report: $CIS_REPORT_HTML (${REPORT_SIZE})"
    fi
    if [ -f "$CIS_REPORT_XML" ]; then
        echo -e "${GREEN}✓${NC} CIS XML report: $CIS_REPORT_XML"
        
        # Parse results
        CIS_PASS=$(grep -c '<result>pass</result>' "$CIS_REPORT_XML" 2>/dev/null || echo "0")
        CIS_FAIL=$(grep -c '<result>fail</result>' "$CIS_REPORT_XML" 2>/dev/null || echo "0")
        TOTAL=$((CIS_PASS + CIS_FAIL))
        if [ $TOTAL -gt 0 ]; then
            COMPLIANCE=$(awk "BEGIN {printf \"%.1f\", ($CIS_PASS / $TOTAL) * 100}")
            echo -e "${BLUE}  CIS Compliance: ${COMPLIANCE}% (${CIS_PASS} pass / ${CIS_FAIL} fail)${NC}"
        fi
    fi
fi

################################################################################
# Cleanup
################################################################################

echo ""
echo -e "${BLUE}[INFO]${NC} Cleaning up..."

docker stop "$CONTAINER_NAME" > /dev/null 2>&1
docker rm "$CONTAINER_NAME" > /dev/null 2>&1

echo -e "${GREEN}✓${NC} Container removed"

################################################################################
# Summary
################################################################################

echo ""
echo "========================================"
echo -e "${GREEN}Compliance Scan Complete${NC}"
echo "========================================"
echo ""
echo "Reports generated in: $REPORT_DIR/"
echo ""
ls -lh "$REPORT_DIR/"*${TIMESTAMP}* 2>/dev/null | awk '{print "  - " $9 " (" $5 ")"}'
echo ""
echo "View reports:"
echo "  Basic:     cat $BASIC_REPORT"
if [ "$USE_SCAP" = true ]; then
    echo "  STIG HTML: xdg-open $STIG_REPORT_HTML"
    echo "  CIS HTML:  xdg-open $CIS_REPORT_HTML"
fi
echo ""

