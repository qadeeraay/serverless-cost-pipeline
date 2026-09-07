# Automated Testing & Benchmark Suite

This directory contains automated testing engines, load generators, and benchmark scripts for validating pipeline performance, resilience, and cost reduction.

---

## Testing Suite Overview

| Script | Purpose | Execution Mode / Options |
|---|---|---|
| [`1_upload_and_process.py`](1_upload_and_process.py) | Synchronous and asynchronous image ingestion | Sync mode (HTTP 200) & Async NATS mode (`--async`) |
| [`2_load_test_autoscaling.py`](2_load_test_autoscaling.py) | Autoscaling and lifecycle validation | Modes: `--mode load`, `--mode lifecycle`, `--mode unit`, `--mode all` |
| [`3_finops_cost_benchmark.py`](3_finops_cost_benchmark.py) | FinOps multi-tier cloud cost benchmarking | Generates p50/p95 latency and cost reduction models |
| [`4_event_driven_s3_trigger.py`](4_event_driven_s3_trigger.py) | Reactive S3 CloudEvent trigger validation | Demonstrates pure `s3:ObjectCreated:Put` event handling |
| [`5_chaos_and_tracing_test.py`](5_chaos_and_tracing_test.py) | Fault injection & distributed tracing | 5-stage attack simulation & W3C distributed trace validation |

---

## Running the Test Suites

### Synchronous and Asynchronous Image Transcoding
```bash
# Synchronous Transcoding
python3 testing_suite/1_upload_and_process.py image_processing/sample_images/modern_architecture.jpg

# Asynchronous Decoupled Ingestion
python3 testing_suite/1_upload_and_process.py --async image_processing/sample_images/cute_dog.jpg
```

### Autoscaling & Lifecycle Engine
```bash
# High-concurrency burst autoscaling test (HPA 1 -> 5 pods)
python3 testing_suite/2_load_test_autoscaling.py --mode load

# Scale-to-zero and cold-start lifecycle validation
python3 testing_suite/2_load_test_autoscaling.py --mode lifecycle

# Automated unit tests
python3 testing_suite/2_load_test_autoscaling.py --mode unit

# Comprehensive suite (runs unit, lifecycle, and load sequentially)
python3 testing_suite/2_load_test_autoscaling.py --mode all
```

### FinOps Cost & Latency Benchmark
```bash
python3 testing_suite/3_finops_cost_benchmark.py
```

### Reactive S3 CloudEvent Trigger
```bash
python3 testing_suite/4_event_driven_s3_trigger.py
```

### Chaos Fault Injection & Distributed Tracing
```bash
python3 testing_suite/5_chaos_and_tracing_test.py
```

---

## Architecture Highlights Demonstrated

* **Event-Driven Decoupling:** Ingestion is decoupled from transcoding via NATS JetStream persistent Write-Ahead Logs, returning an instant `202 Accepted` while serverless workers process batches at optimal throughput.
* **Dead Letter Queues (DLQ):** Payloads failing 3 consecutive attempts are automatically diverted to the `DLQ-POISON` stream (`s3.events.dlq`) to maintain queue processing health.
* **W3C Distributed Tracing:** In-band `traceparent` propagation provides end-to-end distributed latency visibility without heavyweight sidecars.
