# Architecture & System Design Specification

This document details the system design, trust boundaries, event topologies, and architectural trade-offs of the serverless event-driven image processing and FinOps pipeline.

---

## 1. System Architecture & Topology

```mermaid
flowchart TD
    subgraph ClientZone ["1. Traffic Ingestion & Client Tier"]
        Client["Client / Producer<br/>(1_upload_and_process.py)"]
        LoadGen["Load Generator<br/>(2_load_test_autoscaling.py)"]
        S3Trigger["S3 CloudEvent Ingestion<br/>(4_event_driven_s3_trigger.py)"]
        DashUser["DevOps / SRE Operator<br/>(Browser Control Plane :8888)"]
    end

    subgraph StorageBrokerZone ["2. Storage & Event Streaming Tier"]
        MinIO[("MinIO S3 Object Store (:9000)<br/>• uploads/ | processed/ | velero-backups/<br/>• S3 Notification Bridge")]
        JetStream["NATS JetStream Broker (:4222)<br/>• Stream: S3-EVENTS (Persistent WAL)<br/>• Subject: s3.events.*"]
        DLQ["Dead-Letter Queue (DLQ)<br/>• Stream: DLQ-POISON<br/>• Subject: s3.events.dlq"]
    end

    subgraph ComputeZone ["3. Serverless Compute Engine (openfaas & openfaas-fn)"]
        GW["OpenFaaS Gateway (:8080)<br/>• Ingress Reverse Proxy<br/>• Zero-Trust Auth & Routing"]
        Connector["NATS-OpenFaaS Connector<br/>• Durable Pull Consumer<br/>• 5s AckWait & 3-Retry Backoff"]
        HPA["Autoscaling Controller<br/>• HPA v2 (1 to 5 Replicas @ 10% CPU)<br/>• FinOps Auto-Idler (20s Scale-to-Zero)"]
        FuncPod["Hardened Function Pod: image-processor-app<br/>• SecurityContext: UID 1000 Non-Root & readOnlyRootFilesystem<br/>• Engine: Python 3.12 + C-Libwebp (Single-Pass Stream)<br/>• Scratchpad: 32MB /tmp tmpfs In-RAM Scratchpad"]
    end

    subgraph SecurityObservabilityZone ["4. DevSecOps, Observability & Disaster Recovery"]
        NetPol["NetworkPolicy & Cosign Guard<br/>• Egress: minio:9000 & DNS:53 Only<br/>• Cosign ECDSA Container Signature Verification"]
        Prom["Prometheus Telemetry Engine<br/>• :8080/metrics Ingestion & Scrape"]
        DashServer["Real-Time Web Dashboard (:8888)<br/>• Live Pod States & Latency SLA Monitor"]
        VeleroServer["Velero DR S3 Controller v1.15.2<br/>• Daily Cron Snapshots (0 2 * * *)<br/>• Target RTO &lt; 15m, RPO &lt; 1m"]
    end

    %% Flow connections
    Client -->|"1A. Direct Sync HTTP POST"| GW
    Client -->|"1B. Upload Raw Image"| MinIO
    S3Trigger -->|"1C. Direct S3 Trigger"| MinIO
    MinIO -->|"2. s3:ObjectCreated Event"| JetStream
    JetStream -->|"3. Durable Pull Consumer"| Connector
    Connector -->|"4. Dispatch CloudEvent POST"| GW
    LoadGen -.->|"Burst Concurrency Test"| GW
    GW -->|"5. Zero-Trust Ingress (Port 8080)"| FuncPod

    Connector -.->|"On 3 Failures: Poison Route"| DLQ
    Connector -->|"On Success: Event ACK"| JetStream

    HPA -.->|"Dynamic Replica Scaling"| FuncPod
    FuncPod -->|"6. PUT WebP Transcode (Port 9000)"| MinIO

    %% Governance & Observability Links
    NetPol -.->|"Micro-Segmentation & Admission"| FuncPod
    Prom -.->|"Telemetry Scrape"| FuncPod
    Prom -->|"Metrics Stream"| DashServer
    DashUser -->|"Inspect Live Telemetry"| DashServer
    VeleroServer -.->|"Snapshot Cluster State & Config"| FuncPod
    VeleroServer -->|"Stream Tarballs to velero-backups"| MinIO
```

### Live Cluster Topology & Pod Fleet Evidence
![Kubernetes Pod Fleet Overwatch](screenshots/02-k8s-pod-fleet.png)

![Real-Time Observability Dashboard](screenshots/01-observability-dashboard.png)

---

## 2. Zero-Trust Data Flow & Trust Boundaries

```mermaid
sequenceDiagram
    autonumber
    actor User as Client / User
    participant GW as OpenFaaS Gateway (:8080)
    participant NATS as NATS JetStream (:4222)
    participant Conn as NATS-OpenFaaS Connector
    participant Pod as image-processor-app Pod
    participant Storage as MinIO S3 (:9000)
    participant Velero as Velero DR Controller (:velero)

    alt 1. Synchronous Invocation Path
        User->>GW: POST /function/image-processor-app (Image Payload / S3 Ref)
        GW->>Pod: Forward Request to Watchdog (:8080)
        Note over Pod: Security Boundary & In-Memory Pipeline
        rect rgb(240, 248, 255)
            Pod->>Pod: 1. Validate 16-Byte Binary Magic Bytes (PNG/JPEG/WEBP)
            Pod->>Pod: 2. Check 30MP Decompression Cap & Strip EXIF
            Pod->>Pod: 3. In-Memory SHA-256 Cache Check (1.2ms Hit)
            Pod->>Pod: 4. C-Libwebp Transcode (quality=65, method=0) in RAM /tmp
            Pod->>Storage: PUT processed/optimized.webp (TCP 9000)
        end
        Pod-->>GW: HTTP 200 OK + FinOps Telemetry JSON
        GW-->>User: HTTP 200 OK (WebP S3 Ref + Telemetry JSON)
    else 2. Asynchronous Event-Driven Path
        User->>Storage: PUT uploads/raw_image.jpg (S3 API)
        Storage-->>NATS: Publish s3:ObjectCreated:Put Event
        NATS-->>User: HTTP 202 Accepted (Instant Non-Blocking)
        NATS->>Conn: Pull Event Batch (Stream: S3-EVENTS)
        Conn->>GW: POST /function/image-processor-app (CloudEvent)
        GW->>Pod: Forward Request to Pod
        Pod->>Storage: GET uploads/raw_image.jpg
        Pod->>Storage: PUT processed/raw_image_optimized.webp
        Conn->>NATS: ACK Message (or route to DLQ-POISON on 3 failures)
    else 3. Automated Disaster Recovery Backup Path
        Velero->>Storage: Verify S3 Backup Storage Location (velero-backups)
        Velero->>Velero: Execute Daily Cron Snapshot Schedule (0 2 * * *)
        Velero->>Storage: Stream Compressed Tarballs (openfaas, openfaas-fn, nats, minio)
    end
```

### Synchronous In-Memory Transcoding Telemetry
![CLI Transcoding Execution](screenshots/04-cli-transcoding-benchmark.png)

---

## 3. FinOps Multi-Tier Cost Breakdown & Comparison Matrix

| Monthly Workload Volume | Traditional EC2 (`t3.small`) | AWS Lambda (`128MB`) | OpenFaaS on Spot K8s | FinOps Cost Reduction vs VM |
| :--- | :---: | :---: | :---: | :---: |
| **10,000 Invocations** | $\$30.36$ | $\$0.05$ | **$\$0.00$ (Scale-to-Zero)** | **$100.0\%$** |
| **100,000 Invocations** | $\$30.36$ | $\$0.25$ | **$\$0.01$** | **$99.9\%$** |
| **1,000,000 Invocations** | $\$30.36$ | $\$2.25$ | **$\$0.08$** | **$99.7\%$** |
| **10,000,000 Invocations** | $\$30.36$ | $\$22.48$ | **$\$0.77$** | **$97.5\%$** |

### Dynamic Memory Tier Cost Analysis ($1,000,000$ Requests)
* **64 MB Tier:** AWS Lambda: $\$1.22$ vs OpenFaaS Spot: **$\$0.04$**
* **128 MB Tier:** AWS Lambda: $\$2.25$ vs OpenFaaS Spot: **$\$0.08$**
* **256 MB Tier:** AWS Lambda: $\$4.29$ vs OpenFaaS Spot: **$\$0.15$**
* **512 MB Tier:** AWS Lambda: $\$8.38$ vs OpenFaaS Spot: **$\$0.30$**

![FinOps TCO Analysis](screenshots/08-finops-tco-analysis.png)

---

## 4. Function Lifecycle, Cold Starts & Runtime Management

**Cold start path:** OpenFaaS scales `image-processor-app` to `min=1` replica by default (see `function.yaml` labels), so standard traffic hits a warm pod. When the FinOps Idler scales to 0 after inactivity, the *subsequent* request triggers a cold start: the OpenFaaS gateway detects zero ready replicas, the Kubernetes Deployment controller schedules a new pod, the container image is loaded from local cache, the `of-watchdog` process starts, and our handler's module-level `_init_minio_client()` pre-warms the MinIO connection pool before the first request is served. On this cluster that adds roughly 400–800ms versus a warm invocation (container image pull is skipped when cached on the node; latency is dominated by pod scheduling and runtime initialization).

**Runtime management:** The `python3-http` OpenFaaS template runs the handler under a persistent HTTP server (`of-watchdog` in HTTP mode). Unlike standard per-invocation environments, a warm pod serves requests across its lifecycle without re-initializing the Python interpreter or MinIO client each time. Consequently, `_IN_MEMORY_TRANSCODE_CACHE` and the pre-warmed client in `handler.py` remain effective across multiple invocations.

**Resource allocation:** Pod resources are configured with `limits.memory: 256Mi`, `limits.cpu: 2000m`, `requests.memory: 64Mi`, and `requests.cpu: 200m`. This sizing is grounded in observed workload telemetry (peak RSS ~61MB during load testing), providing ample headroom for image decode buffers.

---

## 5. Architectural Limitations & Trade-Offs

| Limitation | Impact on Pipeline | Mitigation & Trade-Off Rationale |
|---|---|---|
| **Cold start latency** | First request after scale-to-zero experiences higher latency | `min=1` replica maintained during peak production hours; cold path enabled for staging and cost-optimized tiers |
| **No long-running state** | Functions cannot maintain durable in-process state | All state lives in MinIO (external object storage); `_IN_MEMORY_TRANSCODE_CACHE` is strictly a best-effort cache |
| **Execution time limits** | `exec_timeout: 10s` caps maximum transcode duration | Single-image transcodes complete in under 20ms; large batch jobs or video would be delegated to asynchronous batch workers (e.g. Argo Workflows) |
| **Observability overhead** | Ephemeral pods require correlated telemetry | Standardized on W3C `traceparent` propagation across gateways, connectors, and handlers |
| **Throughput crossover** | At extremely high continuous request rates, dedicated instances can become cheaper than serverless orchestration | Spot-based serverless is optimal for variable and bursty workloads; sustained workloads can be migrated to dedicated node pools |

---

## 6. Storage Tiering & Data Governance

**Storage structure:** `uploads/` (raw client-submitted assets), `processed/` (optimized WebP deliverables), `raw-images/` and `benchmark/` (reserved for test fixtures, enforced by `ALLOWED_BUCKETS` in `handler.py`). Object keys are strictly validated (`validate_object_key`) before any read or write operation, and destination writes are restricted to the `processed` bucket.

| Raw Image Ingestion (`uploads/`) | Transcoded WebP Deliverables (`processed/`) |
|:---:|:---:|
| ![MinIO Ingestion](screenshots/09-minio-raw-uploads.png) | ![MinIO Distribution](screenshots/10-minio-processed-webp.png) |

**Backup & Disaster Recovery:** Velero is deployed directly in the cluster (`infrastructure/setup_velero.sh`), integrated with the AWS S3 Plugin to stream compressed snapshots (`openfaas`, `openfaas-fn`, `nats`, `minio`) into the `velero-backups` bucket with automated daily schedules (`0 2 * * *`) and full DR restore validation (`./cluster_manage.sh backup-test`).

---

## 7. Full Total Cost of Ownership (TCO)

| Cost Category | Self-Hosted OpenFaaS on K8s | Managed FaaS (e.g. AWS Lambda) |
|---|---|---|
| **Compute (per-invocation)** | ~$0.07 / 1M calls (Spot) | ~$0.25 / 1M calls (128MB) |
| **Kubernetes control plane** | Real cost if managed (e.g. EKS ~$0.10/hr) or $0 on bare-metal/Kind | $0 — fully managed |
| **Worker node baseline** | 1 node runs 24/7 for system pods (GW, NATS, MinIO, CoreDNS) | $0 idle |
| **Observability tooling** | Self-hosted (custom dashboard + Prometheus) | Included in CloudWatch baseline |
| **Maintenance effort** | Cluster upgrades, CVE patching, cert rotation | Provider-managed patching |
| **Data Transfer Out (Egress)** | $0.00 (In-cluster S3 object store) | $0.09 / GB on public AWS |

---

## 8. Architectural Decision Records (ADRs)

### ADR-001: Self-Hosted Kubernetes FaaS vs. Public Cloud Serverless
* **Context:** Operating high-volume media processing workloads on public cloud serverless introduces recurring invocation markups and inter-service egress bandwidth costs.
* **Decision:** Deploy self-hosted OpenFaaS on Kubernetes with Spot instance auto-scaling.
* **Consequences:** Eliminates vendor lock-in, avoids public cloud egress charges, provides full control over low-level Linux security contexts, and achieves over 90% cost reduction at scale.

### ADR-002: Immutable Root Filesystem with RAM-Backed Ephemeral Scratchpad
* **Context:** Applications processing untrusted media streams face risks of remote code execution (RCE) and malicious binary persistence.
* **Decision:** Enforce `readOnlyRootFilesystem: true` combined with an ephemeral RAM-backed volume (`emptyDir: {medium: "Memory"}`) capped at 32MB mounted at `/tmp`.
* **Consequences:** Blocks disk writes and file persistence while providing high-speed in-RAM scratch space (>20 GB/s) for Pillow image streams.

![Hardened Pod SecurityContext Manifest](screenshots/11-hardened-pod-securitycontext.png)

### ADR-003: Dual-Layer Decompression Bomb (Pixel Flood) Mitigation
* **Context:** Attackers can submit small, highly compressed image files that expand into gigabytes in memory, exhausting host RAM.
* **Decision:** Implement dual defense-in-depth:
  1. *Application Layer:* `Image.MAX_IMAGE_PIXELS = 30_000_000` evaluates image dimensions and aborts excessive expansions with HTTP 413 before uncompressing into RAM.
  2. *Infrastructure Layer:* Kubernetes cgroup limits enforce a hard ceiling of `256Mi` RAM per pod.
* **Consequences:** Malicious images are rejected before memory allocation occurs, preventing container OOM kills and protecting host nodes.

### ADR-004: Storage Tier Whitelist & Object Key Path Traversal Defense
* **Context:** Ingestion triggers consuming user-supplied bucket and object keys are vulnerable to Insecure Direct Object Reference (IDOR) and Directory Traversal attacks.
* **Decision:** Enforce an application-level bucket allowlist (`ALLOWED_BUCKETS = {'uploads', 'raw-images', 'processed'}`) and regex validation on object keys to reject directory traversal sequences (`..`), leading slashes, and null bytes.
* **Consequences:** Unauthorized buckets return HTTP 403 Forbidden, and invalid object keys return HTTP 400 Bad Request before invoking MinIO operations.

### ADR-005: Zero-Trust Default-Deny Network Microsegmentation
* **Context:** Compromised worker containers could attempt lateral network discovery or external command-and-control communication.
* **Decision:** Apply a Kubernetes `NetworkPolicy` (`isolate-function-traffic`) with default-deny rules. Whitelist ingress strictly from the OpenFaaS gateway (Port 8080) and egress strictly to MinIO (Port 9000) and CoreDNS (Port 53).
* **Consequences:** Unauthorized outbound network packets are dropped at the Linux kernel level, isolating the compute tier.

### ADR-006: Scale-to-Zero Inactivity Lifecycle & Auto-Idler Governance
* **Context:** Dedicated VM servers incur continuous 24/7 idle costs during low-traffic periods.
* **Decision:** Implement an automated FinOps Idler controller that tracks traffic activity and scales pod replicas to 0 after 20 seconds of inactivity.
* **Consequences:** Reduces compute spend to $0.00 during idle periods, while accepting a 400–800ms cold-start latency when new traffic arrives.

### ADR-007: Binary Magic-Byte Header Verification
* **Context:** Validating input files solely by file extension allows executable scripts to bypass ingestion filters.
* **Decision:** Inspect the first 16 bytes of every uploaded payload for valid binary signatures (`\x89PNG`, `\xff\xd8\xff`, `RIFF/WEBP`).
* **Consequences:** Payloads failing magic-byte validation are rejected immediately with HTTP 422 Unprocessable Entity prior to invoking Pillow image decoding.

### ADR-008: Container Supply-Chain Integrity via Cosign ECDSA Signatures
* **Context:** Container images in public or private registries can be tampered with or replaced with malicious builds.
* **Decision:** Sign container image digests using NIST P-256 elliptic curve keys via Cosign and enforce verification through Kubernetes Admission Controllers.
* **Consequences:** Only cryptographically verified container images matching the trusted public key are admitted to cluster nodes.

![DevSecOps 10/10 and Cosign Signature](screenshots/06-devsecops-audit-cosign.png)

### ADR-009: C-Native Transcoding Optimization
* **Context:** Image transcoding is CPU-intensive; inefficient encoders degrade latency and throughput under load.
* **Decision:** Utilize single-pass C-native WebP encoding with Pillow `method=0` (optimized fast-path) and `quality=65`. Strip EXIF metadata in memory.
* **Consequences:** Reduces median transcode compute latency to under 19 milliseconds while delivering 45%–60% file size reduction.

### ADR-010: Zero Plaintext Credential Management in Git Manifests
* **Context:** Storing storage access keys in Git repositories creates severe security vulnerabilities.
* **Decision:** Store all sensitive credentials in Kubernetes Secrets (`minio-creds`) and inject them into container pods at runtime via `secretKeyRef` and OpenFaaS secret mounts.
* **Consequences:** Manifests checked into version control contain zero plaintext secrets.

### ADR-011: Asynchronous Event-Driven Decoupling via S3 CloudEvents & NATS JetStream
* **Context:** Synchronous HTTP uploads force client connections to block until transcoding completes, increasing timeout risks.
* **Decision:** Decouple ingestion by configuring MinIO S3 bucket notifications (`s3:ObjectCreated:Put`) to publish events into NATS JetStream with a persistent Write-Ahead Log (WAL), consumed by an in-cluster pull connector.
* **Consequences:** Clients receive instant upload confirmations while the serverless function processes transcoding jobs asynchronously with automatic retry backoff and Dead-Letter Queue routing.

### ADR-012: In-Band Distributed Observability via OpenTelemetry W3C TraceContext
* **Context:** Troubleshooting latency bottlenecks in distributed serverless pods requires end-to-end tracing.
* **Decision:** Propagate W3C `traceparent` headers (`00-<trace_id>-<span_id>-01`) across every request, recording discrete sub-millisecond spans for S3 fetch, in-memory C-transcoding, and S3 persistence.
* **Consequences:** Provides granular distributed latency telemetry across all processing phases without heavyweight external sidecars.

---

## 9. Verification & Performance Benchmarking

![Automated Unit and Chaos Test Suite](screenshots/07-unit-chaos-test-suite.png)

```bash
# 1. Master Cluster Audit (Runs DevSecOps, Cosign, Unit, Chaos & FinOps in 1 command):
./cluster_manage.sh audit

# 2. Synchronous & Asynchronous Image Transcoding:
python3 testing_suite/1_upload_and_process.py image_processing/sample_images/modern_architecture.jpg
python3 testing_suite/1_upload_and_process.py --async image_processing/sample_images/cute_dog.jpg

# 3. Unified Serverless Engine (Load Test, Scale-to-Zero & Unit Tests):
python3 testing_suite/2_load_test_autoscaling.py --mode all

# 4. Pure S3 Event-Driven Reactive Ingestion Test:
python3 testing_suite/4_event_driven_s3_trigger.py

# 5. OpenTelemetry W3C Distributed Tracing & Chaos Resilience Suite:
python3 testing_suite/5_chaos_and_tracing_test.py

# 6. FinOps Multi-Tier Cost & Latency Benchmark:
python3 testing_suite/3_finops_cost_benchmark.py

# 7. Real-Time Control Plane Dashboard:
python3 dashboard/server.py
# -> Open http://127.0.0.1:8888 in your browser
```
