# 🛡️ Zero-Trust DevSecOps & Security Suite
**Maintainer:** Qadeer Aslam (qadeer016)  
**Security Baseline:** Cloud-Native Zero-Trust Container & Network Hardening  

---

## 📂 Security Suite Contents & Quick Commands

This directory contains all security configurations, scripts, and cryptographic keys:

| File | Type | Purpose & Scope |
|---|---|---|
| [`1_run_security_audit.py`](1_run_security_audit.py) | **Live Audit Script** | Runs live checks and verifies **10/10 compliance score** |
| [`2_verify_cosign_signature.py`](2_verify_cosign_signature.py) | **Supply-Chain Tool** | Demonstrates **Cosign ECDSA container image signature verification** |
| [`network_policy_and_secrets.yaml`](network_policy_and_secrets.yaml) | **Kubernetes Manifest** | **Zero-Trust NetworkPolicy** (Port 9000 & 53) + Secret encryption |
| [`kyverno_cosign_policy.yaml`](kyverno_cosign_policy.yaml) | **Admission Policy** | **Kyverno Enforce Policy** for Cosign image signature verification |
| [`security_keys/`](security_keys/) | **Key Vault** | ECDSA P-256 `.key`, `.pub`, and `.sig` signature files |

---

## 🚀 How to Run the Security Suite:

```bash
# 1. Run the Complete DevSecOps Security Audit:
python3 security_suite/1_run_security_audit.py

# 2. Run the Cosign Cryptographic Signature Verification:
python3 security_suite/2_verify_cosign_signature.py
```

---

## 🛡️ Core Security Architecture Controls

* **Zero-Trust Microsegmentation:** Enforces default-deny ingress and egress via Kubernetes `NetworkPolicy`. Egress is restricted strictly to MinIO (Port 9000) and CoreDNS (Port 53), preventing lateral movement and external data exfiltration.
* **Host & Runtime Hardening:** Enforces `readOnlyRootFilesystem: true`, non-root execution (`runAsUser: 1000`), and drops all Linux kernel capabilities (`drop: ["ALL"]`). Scratch space is isolated to an in-memory 32MB tmpfs RAM disk.
* **Application-Layer Input Validation:** Inspects 16-byte binary magic headers (`\x89PNG`, `\xff\xd8`, `RIFF/WEBP`) to reject disguised scripts (HTTP 422), enforces a 30-Megapixel ceiling to neutralize Decompression Bomb DoS attacks (HTTP 413), and sanitizes EXIF privacy metadata in-flight.
* **Cryptographic Supply-Chain Integrity:** Verifies container image digest authenticity using Cosign ECDSA NIST P-256 signatures before cluster admission.
