# 🧪 Automated Testing & Performance Suite
**Maintainer:** Qadeer Aslam (qadeer016)  
**Architecture Specification:** Serverless Event-Driven Testing & Benchmarking  

---

## 📂 Streamlined Testing Suite Overview

| Script | Purpose | Execution Mode / Options |
|---|---|---|
| [`1_upload_and_process.py`](file:///home/qadeer/serverless-cost-pipeline/testing_suite/1_upload_and_process.py) | **Instant Image Upload & Transcoding** | Live demo: Sync (HTTP 200) & Async NATS (`--async`) |
| [`2_load_test_autoscaling.py`](file:///home/qadeer/serverless-cost-pipeline/testing_suite/2_load_test_autoscaling.py) | **Unified Testing & Lifecycle Engine** | **Interactive Menu** (Load Test, Scale-to-Zero & Unit Tests) |
| [`3_finops_cost_benchmark.py`](file:///home/qadeer/serverless-cost-pipeline/testing_suite/3_finops_cost_benchmark.py) | **FinOps Multi-Cloud Cost Benchmark** | Generates p50/p95 latency and **99.8% cost savings** report |
| [`4_event_driven_s3_trigger.py`](file:///home/qadeer/serverless-cost-pipeline/testing_suite/4_event_driven_s3_trigger.py) | **Reactive S3 CloudEvent Trigger** | Demonstrates pure `s3:ObjectCreated:Put` event handling |
| [`5_chaos_and_tracing_test.py`](file:///home/qadeer/serverless-cost-pipeline/testing_suite/5_chaos_and_tracing_test.py) | **Chaos & Security Attack Verification** | Automated 5-stage attack & W3C distributed tracing test |

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

## 🔮 Future Scope & Architectural Enhancements (Roadmap)

In enterprise cloud roadmaps, this pipeline can be extended with the following advanced cloud design patterns:

### 1. Asynchronous Queue-Based Load Leveling (OpenFaaS NATS / AWS SQS)
* **Concept:** Decouple the client upload trigger from container execution by publishing image events to a distributed message broker (NATS JetStream / AWS SQS).
* **Benefit:** Returns an instant `202 Accepted` to users in $<2\text{ms}$ while worker pods drain the queue at optimal throughput without dropped connections.

### 2. Dead Letter Queues (DLQ) & Poison Message Handling
* **Concept:** If a corrupted image repeatedly fails decompression, route it to a DLQ for offline forensics without blocking healthy queue traffic.

### 3. Multi-Region Event Streaming (Apache Kafka / AWS EventBridge)
* **Concept:** Ingest image upload events from multiple geographic regions, triggering decentralized serverless edge functions for localized low-latency transcoding.

### 4. Edge AI/ML Automated Content Moderation
* **Concept:** Chain an asynchronous lightweight deep learning model (e.g. YOLOv8 / MobileNet) into the pipeline to classify image content and flag safety violations before storage.
