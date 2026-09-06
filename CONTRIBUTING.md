# Contributing to Serverless DevSecOps & FinOps Pipeline

Thank you for your interest in contributing to the **Serverless Event-Driven Image Processing & FinOps Pipeline**! This document provides guidelines and workflows for proposing enhancements, fixing bugs, and submitting pull requests.

---

## 🏛️ Code of Conduct

All contributors and maintainers are expected to adhere to our [Code of Conduct](CODE_OF_CONDUCT.md). Please report unacceptable behavior through our security contact channels.

---

## 🚀 Getting Started

### 1. Prerequisites
Ensure you have the following tools installed locally:
* **Docker** ($\ge 24.0$)
* **Kind (Kubernetes in Docker)** ($\ge v0.20.0$)
* **kubectl** ($\ge v1.28.0$)
* **Python** ($\ge 3.12$)
* **OpenSSL** (for ECDSA container signature verification)

### 2. Fork and Clone
```bash
git clone https://github.com/<your-username>/serverless-cost-pipeline.git
cd serverless-cost-pipeline
```

### 3. Setup Development Environment
```bash
# Create and activate virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install development dependencies
pip install -r requirements-dev.txt
```

---

## 🛠️ Development & Testing Workflow

We use a root `Makefile` to streamline local development tasks:

| Command | Description |
|---|---|
| `make test` | Executes all unit tests and Chaos/OpenTelemetry resilience suites |
| `make test-unit` | Executes the 10/10 Python unit test suite |
| `make test-chaos` | Executes the 5/5 Chaos & OpenTelemetry tracing tests |
| `make audit` | Runs the 10/10 Enterprise DevSecOps compliance verification |
| `make verify-cosign` | Validates ECDSA NIST P-256 cryptographic supply-chain signature |
| `make bench` | Runs the multi-tier FinOps latency & cloud cost benchmark |
| `make cluster-status` | Displays cluster pod fleet, HPA status, and storage health |
| `make lint` | Validates Python syntax and runs static analysis |

---

## 🛡️ DevSecOps & Quality Standards

Before submitting any code, verify that your changes adhere to our **10/10 DevSecOps Baseline**:
1. **Non-Root Execution**: Container runtimes must run under non-root user (`UID 1000`).
2. **Immutable Filesystem**: `readOnlyRootFilesystem: true` must remain enforced.
3. **Capability Stripping**: Linux capabilities must be explicitly dropped (`drop: ["ALL"]`).
4. **Syscall Filtering**: Seccomp `RuntimeDefault` profile must be applied.
5. **Memory Disk**: In-memory transcoding must use the 32MB `tmpfs` volume (`/tmp`).
6. **Input Validation**: Magic byte checks and path traversal protections must not be bypassed.
7. **Zero Plaintext Secrets**: All sensitive values must be injected via Kubernetes Secrets or file mounts.

---

## 🌿 Git Conventions & Pull Request Guidelines

### Branch Naming
Use descriptive branch names with clear categorization:
* `feat/<feature-description>`
* `fix/<bug-description>`
* `perf/<optimization-description>`
* `sec/<security-enhancement>`
* `docs/<documentation-update>`

### Commit Messages (Conventional Commits)
Follow the [Conventional Commits](https://www.conventionalcommits.org/) specification:
* `feat: add AVIF image transcoding pipeline support`
* `fix: correct bucket notification retry backoff logic`
* `perf: optimize Pillow in-memory buffer allocation`
* `sec: update seccomp profile with tightened syscall filters`
* `docs: update TCO cost benchmark tables in README`

### Submitting a Pull Request
1. Ensure all tests pass: `make test && make audit`
2. Push your changes to your feature branch on your fork.
3. Open a Pull Request targeting the `main` branch.
4. Fill out the [Pull Request Template](.github/PULL_REQUEST_TEMPLATE.md) completely, attaching terminal logs or test output.

---

## 📜 License
By contributing to this repository, you agree that your contributions will be licensed under the project's [MIT License](LICENSE).
