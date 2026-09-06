# 🧪 Automated Testing & Performance Suite
**Maintainer:** Qadeer Aslam (qadeer016)  
**Architecture Specification:** Serverless Event-Driven Testing & Benchmarking  

---

## 📂 Streamlined Testing Suite Overview

| Script | Purpose | Execution Mode / Options |
|---|---|---|
| [`1_upload_and_process.py`](1_upload_and_process.py) | **Instant Image Upload & Transcoding** | Live demo: Sync (HTTP 200) & Async NATS (`--async`) |
| [`2_load_test_autoscaling.py`](2_load_test_autoscaling.py) | **Unified Testing & Lifecycle Engine** | **Interactive Menu** (Load Test, Scale-to-Zero & Unit Tests) |
| [`3_finops_cost_benchmark.py`](3_finops_cost_benchmark.py) | **FinOps Multi-Cloud Cost Benchmark** | Generates p50/p95 latency and **99.8% cost savings** report |
| [`4_event_driven_s3_trigger.py`](4_event_driven_s3_trigger.py) | **Reactive S3 CloudEvent Trigger** | Demonstrates pure `s3:ObjectCreated:Put` event handling |
| [`5_chaos_and_tracing_test.py`](5_chaos_and_tracing_test.py) | **Chaos & Security Attack Verification** | Automated 5-stage attack & W3C distributed tracing test |

---

## 🚀 How to Run the Tests:

### Live Overwatch: Watch Pods Scale in Real Time (Split Terminal)
```bash
watch -n 1 "kubectl get pods -n openfaas-fn -o wide"
```

### Test 1: Upload & Process Any Image (Sync or Async NATS)
```bash
# Synchronous Transcoding
python3 testing_suite/1_upload_and_process.py image_processing/sample_images/modern_architecture.jpg

# Asynchronous Decoupled Ingestion (<55ms Response)
python3 testing_suite/1_upload_and_process.py --async image_processing/sample_images/cute_dog.jpg
```

### Test 2: Unified Serverless Engine (Load Test, Lifecycle & Unit Tests)
```bash
# Mode 1: High-Concurrency Burst Auto-Scaling Stress Test (HPA 1 -> 5 Pods)
python3 testing_suite/2_load_test_autoscaling.py --mode load

# Mode 2: Scale-to-Zero & Cold-Start Lifecycle Proof ($0 Idle Spend)
python3 testing_suite/2_load_test_autoscaling.py --mode lifecycle

# Mode 3: Automated DevSecOps Unit Tests (10/10 Verification)
python3 testing_suite/2_load_test_autoscaling.py --mode unit

# Mode 4: Comprehensive Test Run (Runs Unit -> Lifecycle -> Load sequentially)
python3 testing_suite/2_load_test_autoscaling.py --mode all
```

### Test 3: Run FinOps Cost Reduction & Latency Benchmark
```bash
python3 testing_suite/3_finops_cost_benchmark.py
```

### Test 4: Run Reactive S3 CloudEvent Pipeline (4 Discrete Spans)
```bash
python3 testing_suite/4_event_driven_s3_trigger.py
```

### Test 5: Run Chaos Fault Injection & OpenTelemetry Distributed Tracing
```bash
python3 testing_suite/5_chaos_and_tracing_test.py
```

---

## 🌟 Enterprise Production Features & Roadmap

### Core Production Implementations
* **Asynchronous Event-Driven Decoupling:** Client upload triggers are decoupled from compute execution via NATS JetStream persistent WAL, returning an instant `202 Accepted` while worker pods transcode at optimal throughput.
* **Dead Letter Queues (DLQ) & Poison Message Routing:** Unparseable or malicious payloads failing 3 retry attempts are automatically diverted to the `DLQ-POISON` stream (`s3.events.dlq`) to keep the primary ingestion stream healthy.

### 🔮 Future Architectural Horizons
* **Multi-Region Event Streaming:** Ingest image upload events across multiple cloud regions using geo-distributed streaming brokers and cross-region S3 replication.
* **Next-Gen Web Formats:** Extend C-native engine to support AVIF and JPEG-XL transcoding directly in the 32MB tmpfs RAM scratchpad for an additional 20% egress savings.
* **Edge AI/ML Content Moderation:** Chain lightweight deep learning models (e.g. YOLOv8-nano) to inspect uploaded media for compliance before persisting to durable S3 tiers.

