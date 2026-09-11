#!/usr/bin/env bash
# Configures MinIO bucket notifications to publish Put events to NATS JetStream (s3.events.uploads)
set -euo pipefail

MINIO_ALIAS="local-minio"
MINIO_ENDPOINT="http://127.0.0.1:9000"
MINIO_USER="admin"
MINIO_PASS="password123"

echo "[INFO] Registering mc alias..."
mc alias set "${MINIO_ALIAS}" "${MINIO_ENDPOINT}" "${MINIO_USER}" "${MINIO_PASS}" || mc alias set "${MINIO_ALIAS}" "http://127.0.0.1:31000" "${MINIO_USER}" "${MINIO_PASS}"

echo "[INFO] Ensuring buckets exist..."
mc mb "${MINIO_ALIAS}/uploads" --ignore-existing
mc mb "${MINIO_ALIAS}/processed" --ignore-existing
mc mb "${MINIO_ALIAS}/raw-images" --ignore-existing
mc mb "${MINIO_ALIAS}/benchmark" --ignore-existing

echo "[INFO] Attaching s3:ObjectCreated:Put event -> NATS subject on 'uploads' bucket..."
mc event add "${MINIO_ALIAS}/uploads" arn:minio:sqs::JETSTREAM:nats --event put --ignore-existing 2>/dev/null || mc event add "${MINIO_ALIAS}/uploads" arn:minio:sqs::JETSTREAM:nats --event put || true

echo "[OK] MinIO is now publishing s3:ObjectCreated events to NATS JetStream (subject: s3.events.uploads)."
echo "     Verify with: mc event list ${MINIO_ALIAS}/uploads"
