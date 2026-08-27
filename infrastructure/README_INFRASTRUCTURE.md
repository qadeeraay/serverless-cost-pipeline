# ⚙️ Kubernetes & Cloud Infrastructure Suite
**Maintainer:** Qadeer Aslam (qadeer016)  
**Architecture Specification:** Cloud-Native Serverless & Infrastructure as Code  

---

## 📂 Infrastructure Manifests Overview

| Manifest | Kubernetes Kind | Description & Purpose |
|---|---|---|
| [`k8s-function.yaml`](k8s-function.yaml) | `Deployment`, `Service` | Primary hardened function pod definition (`readOnlyRootFilesystem: true`, UID 1000, RAM `/tmp`) |
| [`hpa.yaml`](hpa.yaml) | `HorizontalPodAutoscaler` | Dynamic elasticity: 1 $\rightarrow$ 5 replicas with 15s rapid scale-down cooldown |
| [`minio.yaml`](minio.yaml) | `Deployment`, `Service` | Decoupled S3 object storage (API Port 9000 & Console Port 9001) |
| [`kind-config.yaml`](kind-config.yaml) | `Cluster` | Local Kubernetes multi-port mapping configuration (8080, 9000, 9001) |
| [`function.yaml`](function.yaml) | `Function` | OpenFaaS Custom Resource Definition (CRD) specification |
| [`nats.yaml`](nats.yaml) | `StatefulSet`, `Service`, `Job` | Real NATS JetStream broker with persistent WAL storage; bootstraps the `S3-EVENTS` and `DLQ-POISON` streams referenced in the failure-handling design |
| [`nats-connector-deployment.yaml`](nats-connector-deployment.yaml) | `Deployment`, `ConfigMap` | Runs `nats_openfaas_connector.py` in-cluster: pulls events off JetStream and invokes the OpenFaaS gateway, with retry/DLQ logic |
| [`configure_minio_nats_bridge.sh`](configure_minio_nats_bridge.sh) | shell script | Wires MinIO bucket notifications to publish real `s3:ObjectCreated` events into NATS JetStream |
| [`setup_velero.sh`](setup_velero.sh) | shell script | Deploys and configures Velero with AWS S3 plugin pointing to MinIO (`velero-backups` bucket) |
| [`backup_restore_demo.sh`](backup_restore_demo.sh) | shell script | Full automated backup creation, MinIO S3 verification, and restore test runner |
| [`velero-schedule.yaml`](velero-schedule.yaml) | `Schedule` | Automated daily snapshot schedule for `openfaas`, `openfaas-fn`, `nats`, and `minio` |

---

## 🚀 How to Apply Infrastructure Changes:

```bash
# Apply hardened function deployment
kubectl apply -f infrastructure/k8s-function.yaml

# Apply Horizontal Pod Autoscaler
kubectl apply -f infrastructure/hpa.yaml

# Apply MinIO S3 storage
kubectl apply -f infrastructure/minio.yaml
```

---

## 🛰️ Deploying the Event Bridge (NATS JetStream — makes the pipeline actually event-driven)

The architecture diagrams describe MinIO → NATS JetStream → OpenFaaS as the event path.
Previously only the diagrams existed; these steps make it real end-to-end on the kind cluster.

```bash
# 1. Deploy NATS JetStream broker + bootstrap the S3-EVENTS / DLQ-POISON streams
kubectl apply -f infrastructure/nats.yaml
kubectl wait --for=condition=ready pod -l app=nats -n nats --timeout=60s

# 2. Deploy the connector that pulls events from JetStream and invokes the function
kubectl create configmap nats-connector-code \
  --from-file=nats_openfaas_connector.py=infrastructure/nats_openfaas_connector.py \
  -n openfaas-fn --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f infrastructure/nats-connector-deployment.yaml

# 3. Wire MinIO bucket notifications into NATS (requires `mc` CLI installed locally)
chmod +x infrastructure/configure_minio_nats_bridge.sh
./infrastructure/configure_minio_nats_bridge.sh

# 4. Verify: upload a file directly to MinIO (not via the test scripts) and confirm
#    the function processes it without any client ever calling the gateway directly.
mc cp image_processing/sample_images/nature_mountain.jpg local-minio/uploads/
kubectl logs -n openfaas-fn -l app=nats-openfaas-connector -f
```

If step 4's log shows `[ACK] Processed event, function returned 200` without you having
invoked the function yourself, the event-driven path is genuinely live and serving requests
in real time.

---

## 🛡️ Disaster Recovery & Backup (Velero + MinIO S3)

Velero is fully integrated with the in-cluster MinIO S3 object storage backend to provide verifiable Kubernetes backup and restore capabilities:

```bash
# 1. Setup / Reconfigure Velero with MinIO S3
./infrastructure/setup_velero.sh

# 2. Run full Disaster Recovery backup & restore verification test
./infrastructure/backup_restore_demo.sh

# 3. Create on-demand backup of serverless namespaces
velero backup create pipeline-manual-backup --include-namespaces openfaas,openfaas-fn,nats,minio --wait

# 4. View active backups in MinIO S3
velero backup get
mc ls local-minio/velero-backups/backups/

# 5. Restore from a backup snapshot
velero restore create --from-backup pipeline-manual-backup --wait
```
