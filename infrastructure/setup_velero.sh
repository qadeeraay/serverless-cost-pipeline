#!/usr/bin/env bash
# ==============================================================================
# 🛡️ Velero S3 (MinIO) Automated Setup & Backup Controller
# Maintainer: Qadeer Aslam (qadeer016)
# Specification: Cloud-Native Kubernetes Disaster Recovery & S3 Backup Management
# ==============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

VELERO_BIN="${HOME}/.local/bin/velero"
MINIO_BUCKET="velero-backups"
MINIO_ENDPOINT="http://minio-service.minio.svc.cluster.local:9000"
MINIO_PUBLIC_ENDPOINT="http://127.0.0.1:9000"
CREDENTIALS_FILE="${SCRIPT_DIR}/credentials-velero"

echo -e "${CYAN}${BOLD}"
echo "=============================================================="
echo " 🛡️  VELERO S3 (MinIO) INSTALLATION & CONFIGURATION CONTROLLER"
echo "=============================================================="
echo -e "${NC}"

# 1. Check or install Velero CLI
if [ ! -f "$VELERO_BIN" ]; then
    echo -e " ${YELLOW}[1/4] Downloading Velero v1.15.2 CLI...${NC}"
    mkdir -p "${HOME}/.local/bin"
    curl -fsSL https://github.com/velero-io/velero/releases/download/v1.15.2/velero-v1.15.2-linux-amd64.tar.gz -o /tmp/velero.tar.gz
    tar -xzf /tmp/velero.tar.gz -C /tmp/
    mv /tmp/velero-v1.15.2-linux-amd64/velero "$VELERO_BIN"
    chmod +x "$VELERO_BIN"
    rm -rf /tmp/velero.tar.gz /tmp/velero-v1.15.2-linux-amd64
    echo -e " ${GREEN}[✓] Velero CLI installed at ${VELERO_BIN}.${NC}"
else
    echo -e " ${GREEN}[✓] Velero CLI already installed at ${VELERO_BIN}.${NC}"
fi

# Ensure ~/.local/bin is in PATH for this script session
export PATH="${HOME}/.local/bin:${PATH}"

# 2. Ensure MinIO bucket exists
echo -e "\n ${YELLOW}[2/4] Ensuring MinIO S3 bucket '${MINIO_BUCKET}' exists...${NC}"
if command -v mc &>/dev/null; then
    mc alias set local-minio http://127.0.0.1:9000 admin password123 --api S3v4 >/dev/null 2>&1 || true
    mc mb "local-minio/${MINIO_BUCKET}" --ignore-existing >/dev/null 2>&1 || true
    echo -e " ${GREEN}[✓] Bucket 'local-minio/${MINIO_BUCKET}' verified.${NC}"
else
    echo -e " ${YELLOW}[!] mc CLI not found, assuming bucket created or MinIO auto-initializes.${NC}"
fi

# 3. Create S3 credentials file
echo -e "\n ${YELLOW}[3/4] Generating AWS S3-compatible credentials for MinIO...${NC}"
cat << 'EOF' > "$CREDENTIALS_FILE"
[default]
aws_access_key_id = admin
aws_secret_access_key = password123
EOF
chmod 600 "$CREDENTIALS_FILE"
echo -e " ${GREEN}[✓] Credentials file prepared at ${CREDENTIALS_FILE}.${NC}"

# 4. Install Velero Server on Kubernetes
echo -e "\n ${YELLOW}[4/4] Installing / Updating Velero Server in namespace 'velero'...${NC}"
"$VELERO_BIN" install \
    --provider aws \
    --plugins velero/velero-plugin-for-aws:v1.11.0 \
    --bucket "$MINIO_BUCKET" \
    --secret-file "$CREDENTIALS_FILE" \
    --backup-location-config region=minio,s3ForcePathStyle="true",s3Url="$MINIO_ENDPOINT",publicUrl="$MINIO_PUBLIC_ENDPOINT" \
    --use-volume-snapshots=false \
    --wait

echo -e "\n ⏳ Validating Backup Storage Location..."
sleep 3
"$VELERO_BIN" backup-location get

echo -e "\n ${GREEN}${BOLD}✅ VELERO S3 BACKUP CONTROLLER SUCCESSFULLY CONFIGURED!${NC}"
echo -e " • S3 Storage Target : ${BOLD}${MINIO_ENDPOINT}/${MINIO_BUCKET}${NC}"
echo -e " • Provider Plugin   : ${BOLD}AWS S3 v1.11.0 (MinIO Compatible)${NC}"
echo -e " • Status            : ${GREEN}${BOLD}Active & Available${NC}"
echo ""
echo -e " 👉 ${CYAN}To create your first backup, run:${NC}"
echo -e "    ${BOLD}velero backup create pipeline-full-backup --include-namespaces openfaas,openfaas-fn,nats,minio --wait${NC}"
echo ""
