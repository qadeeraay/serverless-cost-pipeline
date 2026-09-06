# 🛡️ Security Policy & Zero-Trust Governance

The **Serverless Event-Driven Image Processing & FinOps Pipeline** is designed with a defense-in-depth, Zero-Trust security architecture. We take the security and integrity of this project very seriously.

---

## 📋 Supported Versions

Security patches and vulnerability updates are actively maintained on the following branches:

| Version | Supported | Notes |
|:---|:---:|:---|
| `main` / `v2.x` | ✅ | Active production development & DevSecOps baseline |
| `< v2.0` | ❌ | Deprecated legacy releases |

---

## 🔒 Zero-Trust Security Architecture

This project strictly enforces **10 Enterprise DevSecOps & Cloud-Native Security Controls**:

1. **Network Segmentation**: Micro-segmentation via Kubernetes `NetworkPolicy` (`isolate-function-traffic`). Ingress restricted strictly to OpenFaaS Gateway (`TCP 8080`), egress restricted to MinIO (`TCP 9000`) and CoreDNS (`UDP/TCP 53`).
2. **Immutable Root Filesystem**: `readOnlyRootFilesystem: true` prevents unauthorized binary writes, malware persistence, and runtime configuration tampering.
3. **Non-Root Execution**: Function containers execute with unprivileged user ID (`runAsUser: 1000`, `runAsNonRoot: true`), eliminating container breakout risks.
4. **Linux Capability Dropping**: Drops all 38+ kernel root capabilities (`capabilities: drop: ["ALL"]`).
5. **Seccomp Syscall Filtering**: Restricts dangerous kernel system calls using the container runtime default seccomp profile (`RuntimeDefault`).
6. **Encrypted Secret Management**: Injects zero plaintext credentials into code or Git repositories. Credentials load via `secretKeyRef` into ephemeral tmpfs mounts.
7. **Ephemeral RAM-Backed Scratchpad**: Direct memory processing with 32MB tmpfs RAM disk (`emptyDir: medium: Memory`) prevents residual disk storage.
8. **Supply-Chain Container Signing**: Cryptographic container image verification via **Cosign NIST P-256 ECDSA** digital signatures.
9. **Decompression Bomb Defense**: `Image.MAX_IMAGE_PIXELS = 30_000_000` rejects malicious image bombs before memory decompression occurs.
10. **Binary Magic Byte Inspection**: Strict binary header validation (`\x89PNG`, `\xff\xd8`, `RIFF/WEBP`) stops disguised executable script uploads.

---

## 🚨 Reporting a Vulnerability

If you discover a potential security vulnerability or misconfiguration, please **do not open a public GitHub issue**.

### Reporting Process
1. Contact the maintainer directly via email: **qadeeraslam016@gmail.com** (or open a private GitHub Security Advisory).
2. Include the following details in your report:
   - Type of issue (e.g. privilege escalation, container escape, bypass of input filtering, denial of service).
   - Component affected (e.g. `handler.py`, `infrastructure/k8s-function.yaml`, `nats-openfaas-connector.py`).
   - Step-by-step instructions or proof-of-concept (PoC) to reproduce the vulnerability.
   - Recommended remediation or mitigation steps.

### Response Timeline
* **Initial Acknowledgement**: Within 24 hours.
* **Triage & Vulnerability Assessment**: Within 48 hours.
* **Security Patch Release**: Within 7 business days depending on severity.

---

## 📜 Cryptographic Signature Verification
You can independently verify the supply-chain integrity of our container image using OpenSSL or Cosign:
```bash
python3 security_suite/2_verify_cosign_signature.py
```
Verification public key is available at [`security_suite/security_keys/cosign_ecdsa.pub`](security_suite/security_keys/cosign_ecdsa.pub).
