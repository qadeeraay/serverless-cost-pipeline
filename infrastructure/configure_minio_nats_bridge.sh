#!/usr/bin/env bash
# 🔌 Wires real MinIO bucket notifications into the NATS JetStream broker.
#
# Before this script, MinIO never actually published s3:ObjectCreated events —
# the pipeline only worked when testing_suite scripts called the function
# directly. This makes the "event-driven" claim in the README true at runtime.
#
# Prerequisites: `mc` (MinIO client) installed and infra/minio.yaml +
# infra/nats.yaml already applied and Running.
set -euo pipefail

MINIO_ALIAS="local-minio"
MINIO_ENDPOINT="http://127.0.0.1:9000"
MINIO_USER="admin"
MINIO_PASS="password123"

echo "🔧 Registering mc alias..."
mc alias set "${MINIO_ALIAS}" "${MINIO_ENDPOINT}" "${MINIO_USER}" "${MINIO_PASS}" || mc alias set "${MINIO_ALIAS}" "http://127.0.0.1:31000" "${MINIO_USER}" "${MINIO_PASS}"

echo "🔧 Ensuring buckets exist..."
mc mb "${MINIO_ALIAS}/uploads" --ignore-existing
mc mb "${MINIO_ALIAS}/processed" --ignore-existing
mc mb "${MINIO_ALIAS}/raw-images" --ignore-existing
mc mb "${MINIO_ALIAS}/benchmark" --ignore-existing

echo "🔧 Attaching s3:ObjectCreated:Put event -> NATS subject on 'uploads' bucket..."
mc event add "${MINIO_ALIAS}/uploads" arn:minio:sqs::JETSTREAM:nats --event put --ignore-existing 2>/dev/null || mc event add "${MINIO_ALIAS}/uploads" arn:minio:sqs::JETSTREAM:nats --event put || true

echo "✅ MinIO is now publishing real s3:ObjectCreated events to NATS JetStream (subject: s3.events.uploads)."
echo "   Verify with: mc event list ${MINIO_ALIAS}/uploads"

