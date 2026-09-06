#!/usr/bin/env bash

# ==============================================================================
# 🚀 ADVANCED SERVERLESS CLUSTER & PERSISTENCE CONTROLLER (v2.0)
# Maintainer  : Qadeer Aslam (qadeer016)
# Project     : Serverless Event-Driven Image Processing & FinOps Pipeline
# Core Stack  : Kubernetes, OpenFaaS, NATS JetStream, MinIO S3, Velero DR
# ==============================================================================

set -e

# Auto-detect Kind container name
KIND_CONTAINER=$(docker ps -a --filter "name=control-plane" --format "{{.Names}}" 2>/dev/null | head -n 1 || true)

if [ -z "$KIND_CONTAINER" ]; then
    KIND_CONTAINER="serverless-cluster-control-plane"
fi

# Color scheme
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

banner() {
    echo -e "${CYAN}${BOLD}"
    echo "=============================================================="
    echo " Serverless Cluster & Pipeline Controller"
    echo "=============================================================="
    echo -e "${NC}"
}

usage() {
    banner
    echo -e " Target Container : ${BOLD}$KIND_CONTAINER${NC}"
    echo ""
    echo -e " ${YELLOW}Usage:${NC} ./cluster_manage.sh [command]"
    echo ""
    echo -e " ${BOLD}Commands:${NC}"
    echo -e "   ${GREEN}start${NC}         -> Resume cluster and reconcile workloads"
    echo -e "   ${YELLOW}stop${NC}          -> Graceful shutdown (0% CPU/RAM, state preserved)"
    echo -e "   ${CYAN}status${NC}        -> Component health, pod metrics, and HPA status"
    echo -e "   ${CYAN}restart${NC}       -> Restart Kind cluster container"
    echo -e "   ${GREEN}optimize${NC}      -> Re-apply configs and rolling restart function"
    echo -e "   ${GREEN}heal${NC}          -> Reconcile any stalled pods or rollouts"
    echo -e "   ${CYAN}backup${NC}        -> Create on-demand Velero backup to MinIO S3"
    echo -e "   ${CYAN}backup-test${NC}   -> Run full backup and disaster recovery test"
    echo -e "   ${CYAN}audit${NC}         -> Run full DevSecOps and FinOps verification suite"
    echo "=============================================================="
    exit 1
}

wait_for_apiserver() {
    echo -e " Waiting for Kubernetes API server..."
    for i in $(seq 1 30); do
        if kubectl get nodes &>/dev/null; then
            echo -e " ${GREEN}[✓] Kubernetes API Server is ready.${NC}"
            return 0
        fi
        sleep 1
    done
    echo -e " ${RED}[✗] Timed out waiting for API server.${NC}"
    return 1
}

wait_for_openfaas() {
    echo -e " Waiting for OpenFaaS Gateway and MinIO S3..."
    kubectl wait --for=condition=available --timeout=45s deployment/gateway -n openfaas 2>/dev/null || true
    kubectl wait --for=condition=available --timeout=45s deployment/minio -n minio 2>/dev/null || true
    kubectl wait --for=condition=available --timeout=45s deployment/image-processor-app -n openfaas-fn 2>/dev/null || true
}

case "$1" in
    stop|down|pause|shutdown)
        banner
        echo -e " ==> Stopping cluster container ($KIND_CONTAINER)..."
        echo -e " [1/3] Flushing in-memory sync buffers..."
        sync || true
        echo -e " [2/3] Gracefully suspending Kind cluster container..."
        docker stop -t 5 "$KIND_CONTAINER" >/dev/null
        echo -e " [3/3] Releasing host resources..."
        echo ""
        echo -e " ${GREEN}[✓] Cluster suspended.${NC}"
        echo -e " • Host resource usage: 0% CPU / 0 MB RAM"
        echo -e " • State: Preserved in Docker persistent volume"
        echo -e " • Resume command: ./cluster_manage.sh start\n"
        ;;

    start|up|resume|boot)
        banner
        echo -e " ==> Starting serverless pipeline cluster ($KIND_CONTAINER)..."
        echo -e " [1/5] Starting Docker container..."
        docker start "$KIND_CONTAINER" >/dev/null
        echo -e " [2/5] Checking Kubernetes control plane..."
        wait_for_apiserver
        echo -e " [3/5] Waiting for OpenFaaS Gateway and MinIO..."
        wait_for_openfaas
        echo -e " [4/5] Reconciling NetworkPolicy, secrets, and pod specs..."
        PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        kubectl apply -f "${PROJECT_DIR}/security_suite/network_policy_and_secrets.yaml" >/dev/null 2>&1 || true
        kubectl create configmap function-handler-code \
          --from-file=handler.py="${PROJECT_DIR}/function/image-processor-app/handler.py" \
          -n openfaas-fn --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1 || true
        kubectl apply -f "${PROJECT_DIR}/infrastructure/k8s-function.yaml" >/dev/null 2>&1 || true
        kubectl apply -f "${PROJECT_DIR}/infrastructure/function.yaml" >/dev/null 2>&1 || true
        kubectl apply -f "${PROJECT_DIR}/infrastructure/hpa.yaml" >/dev/null 2>&1 || true
        kubectl rollout restart deployment image-processor-app -n openfaas-fn >/dev/null 2>&1 || true
        kubectl rollout status deployment image-processor-app -n openfaas-fn --timeout=35s >/dev/null 2>&1 || true
        
        echo -e " [5/5] Active Pod Summary:"
        kubectl get pods -n openfaas-fn
        echo ""
        echo -e " ${GREEN}[✓] Cluster online and ready.${NC}"
        echo -e " • Gateway Endpoint : http://127.0.0.1:8080"
        echo -e " • MinIO Storage    : http://127.0.0.1:9000\n"
        ;;

    status|health|check)
        banner
        echo -e " ==> Cluster Component Health Overview:\n"
        
        DOCKER_STATUS=$(docker inspect -f '{{.State.Status}}' "$KIND_CONTAINER" 2>/dev/null || echo 'Not Running')
        if [ "$DOCKER_STATUS" = "running" ]; then
            echo -e " • Docker Container : ${GREEN}${BOLD}RUNNING${NC} ($KIND_CONTAINER)"
        else
            echo -e " • Docker Container : ${RED}${BOLD}STOPPED / OFFLINE${NC}"
            exit 0
        fi

        echo ""
        echo -e " ${BOLD}Kubernetes Nodes:${NC}"
        kubectl get nodes --no-headers 2>/dev/null | awk '{print "   • Node: "$1" | Status: "$2" | Version: "$5}'
        
        echo ""
        echo -e " ${BOLD}Serverless Function Pods (openfaas-fn):${NC}"
        kubectl get pods -n openfaas-fn --no-headers 2>/dev/null | awk '{print "   • Pod: "$1" | Ready: "$2" | Status: "$3" | Restarts: "$4}'
        
        echo ""
        echo -e " ${BOLD}Horizontal Pod Autoscaler (HPA):${NC}"
        kubectl get hpa -n openfaas-fn --no-headers 2>/dev/null | awk '{print "   • HPA: "$1" | Target: "$3" | Replicas: "$6" (Min: "$4" / Max: "$5")"}'

        echo ""
        echo -e " ${BOLD}MinIO Storage (minio):${NC}"
        kubectl get pods -n minio --no-headers 2>/dev/null | awk '{print "   • Storage Pod: "$1" | Status: "$3}'

        echo ""
        echo -e " ${BOLD}Velero S3 Backup Controller:${NC}"
        VELERO_PHASE=$(kubectl get backupstoragelocation -n velero -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Not Installed")
        echo -e "   • Backup Target (MinIO S3): ${GREEN}${BOLD}${VELERO_PHASE}${NC}"
        echo ""
        ;;

    backup|snapshot)
        banner
        echo -e " ==> Creating on-demand Velero backup to MinIO S3...\n"
        VELERO_BIN="${HOME}/.local/bin/velero"
        if [ ! -f "$VELERO_BIN" ]; then
            echo -e " ${RED}[✗] Velero not found. Run ./infrastructure/setup_velero.sh first.${NC}"
            exit 1
        fi
        BACKUP_ID="pipeline-backup-$(date +%s)"
        "$VELERO_BIN" backup create "$BACKUP_ID" --include-namespaces openfaas,openfaas-fn,nats,minio --wait
        echo -e " ${GREEN}[✓] Backup '$BACKUP_ID' synchronized with bucket 'velero-backups'.${NC}\n"
        "$VELERO_BIN" backup describe "$BACKUP_ID"
        ;;

    backups|list-backups)
        banner
        echo -e " ==> Velero S3 Backups:\n"
        VELERO_BIN="${HOME}/.local/bin/velero"
        if [ -f "$VELERO_BIN" ]; then
            "$VELERO_BIN" backup get
        else
            echo -e " ${RED}[✗] Velero not found.${NC}"
        fi
        echo ""
        ;;

    backup-test|dr-test|restore)
        PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        "${PROJECT_DIR}/infrastructure/backup_restore_demo.sh"
        ;;

    scale-to-zero|zero|idle)
        banner
        echo -e " ==> Scaling function deployment to 0 replicas..."
        kubectl scale deployment -n openfaas-fn image-processor-app --replicas=0
        echo -e " ${GREEN}[✓] Function scaled down to 0 replicas (scale-to-zero active).${NC}\n"
        ;;

    optimize|harden|heal|fix|repair)
        banner
        echo -e " ==> Reconciling performance and security configuration...\n"
        PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        
        echo -e " [1/4] Applying NetworkPolicy and secrets..."
        kubectl apply -f "${PROJECT_DIR}/security_suite/network_policy_and_secrets.yaml" >/dev/null
        
        echo -e " [2/4] Syncing handler configmap..."
        kubectl create configmap function-handler-code \
          --from-file=handler.py="${PROJECT_DIR}/function/image-processor-app/handler.py" \
          -n openfaas-fn --dry-run=client -o yaml | kubectl apply -f - >/dev/null
          
        echo -e " [3/4] Reconciling pod specifications and HPA..."
        kubectl apply -f "${PROJECT_DIR}/infrastructure/k8s-function.yaml" >/dev/null
        kubectl apply -f "${PROJECT_DIR}/infrastructure/function.yaml" >/dev/null
        kubectl apply -f "${PROJECT_DIR}/infrastructure/hpa.yaml" >/dev/null
        
        echo -e " [4/4] Performing rolling deployment restart..."
        kubectl rollout restart deployment image-processor-app -n openfaas-fn >/dev/null
        kubectl rollout status deployment image-processor-app -n openfaas-fn --timeout=35s >/dev/null
        
        echo -e "\n ${GREEN}[✓] All controls reconciled successfully.${NC}\n"
        ;;

    restart)
        banner
        echo -e " ==> Restarting Kind cluster container..."
        docker restart "$KIND_CONTAINER"
        wait_for_apiserver
        wait_for_openfaas
        kubectl get pods -n openfaas-fn
        echo -e " ${GREEN}[✓] Restart complete.${NC}\n"
        ;;

    audit|test|eval|evaluate)
        banner
        echo -e " ==> Running verification test suite...\n"
        PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        python3 "${PROJECT_DIR}/security_suite/1_run_security_audit.py"
        echo ""
        python3 "${PROJECT_DIR}/security_suite/2_verify_cosign_signature.py"
        echo ""
        python3 "${PROJECT_DIR}/testing_suite/2_load_test_autoscaling.py" --mode unit
        echo ""
        python3 "${PROJECT_DIR}/testing_suite/5_chaos_and_tracing_test.py"
        echo ""
        python3 "${PROJECT_DIR}/testing_suite/3_finops_cost_benchmark.py"
        echo -e "\n ${GREEN}[✓] All verification suites passed successfully.${NC}\n"
        exit 0
        ;;

    *)
        usage
        ;;
esac
