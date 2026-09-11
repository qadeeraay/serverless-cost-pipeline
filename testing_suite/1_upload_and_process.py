#!/usr/bin/env python3
"""
🚀 Instant Image Uploader & Serverless Optimizer CLI
Usage: python3 1_upload_and_process.py <path_to_image>
"""

import sys
import os
import time
import requests
from minio import Minio

MINIO_ENDPOINT = "127.0.0.1:9000"
MINIO_ACCESS_KEY = "admin"
MINIO_SECRET_KEY = "password123"
OPENFAAS_GATEWAY = "http://127.0.0.1:8080"
BASE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
DEFAULT_OUTPUT_DIR = os.path.join(BASE_DIR, "image_processing", "processed_output")
SUPPORTED_EXTS = ('.png', '.jpg', '.jpeg', '.webp', '.bmp', '.tiff')

def main():
    is_async = "--async" in sys.argv
    file_args = [arg for arg in sys.argv[1:] if not arg.startswith("--")]
    
    if file_args:
        file_path = file_args[0]
    else:
        # Default to bundled high-res sample image
        file_path = os.path.join(BASE_DIR, "image_processing", "sample_images", "mountain_landscape.jpg")

    if not os.path.exists(file_path):
        print(f"\n❌ Error: File not found at '{file_path}'\n")
        sys.exit(1)

    filename = os.path.basename(file_path)
    base_name, ext = os.path.splitext(filename)

    if not ext.lower().endswith(SUPPORTED_EXTS):
        print(f"\nError: Unsupported format '{ext}'. Supported: {SUPPORTED_EXTS}\n")
        sys.exit(1)

    orig_size = os.path.getsize(file_path)

    print("==========================================================")
    print(" Serverless Image Processing & Optimization CLI")
    print(f" Mode: {'Asynchronous NATS Ingestion' if is_async else 'Synchronous Ingestion'}")
    print("==========================================================")
    print(f" Source: {filename} ({orig_size:,} bytes)")

    # 1. Connect to MinIO
    client = Minio(MINIO_ENDPOINT, access_key=MINIO_ACCESS_KEY, secret_key=MINIO_SECRET_KEY, secure=False)
    for b in ["uploads", "processed"]:
        if not client.bucket_exists(b):
            client.make_bucket(b)

    # 2. Upload to MinIO 'uploads' bucket
    content_type = f"image/{ext.replace('.', '').lower()}"
    client.fput_object("uploads", filename, file_path, content_type=content_type)
    print(f" [✓] 1. Uploaded to MinIO 'uploads/{filename}'")

    # 3. Trigger Serverless OpenFaaS Function
    endpoint = f"{OPENFAAS_GATEWAY}/async-function/image-processor-app" if is_async else f"{OPENFAAS_GATEWAY}/function/image-processor-app"
    print(" [*] 2. Triggering function endpoint...")
    start_time = time.time()
    
    pass_output = os.popen('kubectl get secret -n openfaas basic-auth -o jsonpath="{.data.basic-auth-password}" | base64 --decode').read().strip()
    
    event_payload = {
        "Records": [
            {
                "eventSource": "minio:s3",
                "eventName": "s3:ObjectCreated:Put",
                "s3": {
                    "bucket": {"name": "uploads"},
                    "object": {"key": filename, "size": orig_size}
                }
            }
        ]
    }

    if is_async:
        # High-Speed NATS Async Invocation (<2ms)
        resp = requests.post(
            endpoint,
            auth=('admin', pass_output),
            json=event_payload,
            headers={"Content-Type": "application/json"},
            timeout=5
        )
        latency = round((time.time() - start_time) * 1000, 2)
        if resp.status_code == 202:
            print(f" [✓] 3. Ingestion acknowledged in {latency} ms (HTTP 202 Accepted)")
            print("\n" + "="*58)
            print(" Asynchronous Event Metrics")
            print("="*58)
            print(" • Mode                : Asynchronous NATS Decoupled")
            print(f" • Client Latency      : {latency} ms")
            print(" • Pipeline            : WebP transcoding to processed/ bucket")
            print(" • Scaling Behavior    : Handled via NATS queue-worker")
            print("="*58)
            print(" [✓] Image queued for background transcoding.\n")
            return
        else:
            print(f" [✗] Async invocation failed: HTTP {resp.status_code}")
            return

    # Synchronous Invocation
    resp = None
    for attempt in range(12):
        try:
            resp = requests.post(
                endpoint,
                auth=('admin', pass_output),
                json=event_payload,
                headers={"Content-Type": "application/json"},
                timeout=15
            )
            if resp.status_code == 200:
                break
            time.sleep(0.3)
        except Exception:
            time.sleep(0.3)

    latency = round((time.time() - start_time) * 1000, 2)
    
    if resp and resp.status_code == 200:
        data = resp.json()
        metrics = data.get("image_metrics", {})
        webp_info = metrics.get("optimized_webp", {})
        telemetry = data.get("telemetry", {})

        print(f" [✓] 3. Serverless processing completed in {latency} ms (HTTP 200 OK)")
        print("\n" + "="*58)
        print(" Optimization Results & Telemetry")
        print("="*58)
        print(f" • Dimensions          : {metrics.get('dimensions', {}).get('width')}x{metrics.get('dimensions', {}).get('height')} px")
        print(f" • WebP File           : {webp_info.get('key')} ({webp_info.get('size_bytes', 0):,} bytes)")
        print(f" • Bandwidth Reduction : {webp_info.get('compression_savings')}")
        print(" • Transcoding Engine  : Pillow (libwebp C-extension)")
        print(" • Security Context    : Magic bytes validated, read-only rootfs, EXIF stripped")
        print(f" • Compute Duration    : {telemetry.get('execution_duration_ms')} ms")
        print(f" • Est. Invocation Cost: {telemetry.get('self_hosted_k8s_spot_cost_usd')}")
        print("="*58)

        # 4. Download processed output
        os.makedirs(DEFAULT_OUTPUT_DIR, exist_ok=True)
        webp_local = os.path.join(DEFAULT_OUTPUT_DIR, webp_info.get('key', 'optimized.webp'))
        client.fget_object("processed", webp_info.get('key'), webp_local)
        print(f"\n Downloaded optimized result:\n  {webp_local}\n")

    else:
        status = resp.status_code if resp else 'No response'
        text = resp.text if resp else ''
        print(f" [✗] Processing failed with status {status}: {text}")

if __name__ == "__main__":
    main()
