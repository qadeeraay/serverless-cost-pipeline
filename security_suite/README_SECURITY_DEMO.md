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

## 🚀 How to Run the Security Demo in 2 Commands:

```bash
# 1. Run the Complete 10/10 DevSecOps Security Audit:
python3 /home/qadeer/serverless-cost-pipeline/security_suite/1_run_security_audit.py
```

```bash
# 2. Run the Cosign Cryptographic Signature Verification:
python3 /home/qadeer/serverless-cost-pipeline/security_suite/2_verify_cosign_signature.py
```

---

## 🎯 Key Security Architecture Highlights:

1. **Network Security:** *"We enforce Zero-Trust micro-segmentation using a Kubernetes `NetworkPolicy`. Egress is blocked by default, allowing connections strictly to MinIO (Port 9000) and CoreDNS (Port 53)."*
2. **Host & Container Hardening:** *"The container operates with `readOnlyRootFilesystem: true`, non-root user UID 1000, and all Linux kernel capabilities dropped (`drop: ALL`). Scratch space is restricted to a 32MB in-memory RAM volume."*
3. **Application Layer:** *"The function inspects binary magic bytes (`\x89PNG`, `\xff\xd8`) to prevent script injection and enforces `MAX_IMAGE_PIXELS = 30M` to neutralize Decompression Bomb DoS attacks."*
4. **Supply-Chain Integrity:** *"Every container artifact built for `docker.io/qadeer016/image-processor-app` is digitally signed using ECDSA NIST P-256 keys via Cosign."*
