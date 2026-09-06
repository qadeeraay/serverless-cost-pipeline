# DevSecOps & Security Suite

This directory contains security configurations, verification scripts, and cryptographic keys implementing the zero-trust container and network security baseline.

---

## Directory Contents

| File | Type | Purpose & Scope |
|---|---|---|
| [`1_run_security_audit.py`](1_run_security_audit.py) | Audit Script | Runs automated checks and verifies the 10/10 compliance score |
| [`2_verify_cosign_signature.py`](2_verify_cosign_signature.py) | Verification Tool | Demonstrates Cosign ECDSA container image signature verification |
| [`network_policy_and_secrets.yaml`](network_policy_and_secrets.yaml) | Kubernetes Manifest | Zero-Trust NetworkPolicy (Port 9000 & 53) and Secret configuration |
| [`kyverno_cosign_policy.yaml`](kyverno_cosign_policy.yaml) | Admission Policy | Kyverno Enforce Policy for Cosign image signature verification |
| [`security_keys/`](security_keys/) | Key Vault | ECDSA P-256 public key (`.pub`), manifest, and `.sig` signature |

---

## Running Verification

```bash
# 1. Run DevSecOps security audit:
python3 security_suite/1_run_security_audit.py

# 2. Run Cosign signature verification:
python3 security_suite/2_verify_cosign_signature.py
```

---

## Core Security Controls

* **Zero-Trust Microsegmentation:** Enforces default-deny ingress and egress via Kubernetes `NetworkPolicy`. Egress is restricted strictly to MinIO (Port 9000) and CoreDNS (Port 53), preventing lateral movement and external data exfiltration.
* **Host & Runtime Hardening:** Enforces `readOnlyRootFilesystem: true`, non-root execution (`runAsUser: 1000`), and drops all Linux kernel capabilities (`drop: ["ALL"]`). Scratch space is isolated to an in-memory 32MB tmpfs RAM disk.
* **Application-Layer Input Validation:** Inspects 16-byte binary magic headers (`\x89PNG`, `\xff\xd8`, `RIFF/WEBP`) to reject disguised scripts (HTTP 422), enforces a 30-Megapixel ceiling to neutralize Decompression Bomb DoS attacks (HTTP 413), and sanitizes EXIF privacy metadata in-flight.
* **Cryptographic Supply-Chain Integrity:** Verifies container image digest authenticity using Cosign ECDSA NIST P-256 signatures before cluster admission.
