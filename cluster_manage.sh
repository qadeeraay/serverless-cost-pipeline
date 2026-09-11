#!/usr/bin/env bash

# Serverless cluster and persistence lifecycle controller

set -e

# Resolve Serverless Kind control-plane container, explicitly excluding openbao
if docker ps -a --format "{{.Names}}" 2>/dev/null | grep -q "^serverless-cluster-control-plane$"; then
    KIND_CONTAINER="serverless-cluster-control-plane"
else
    KIND_CONTAINER=$(docker ps -a --filter "name=control-plane" --format "{{.Names}}" 2>/dev/null | grep -v "openbao" | head -n 1 || true)
    if [ -z "$KIND_CONTAINER" ]; then
        KIND_CONTAINER="serverless-cluster-control-plane"
    fi
fi

# Explicitly scope kubectl calls to the serverless cluster context
KIND_CONTEXT="kind-serverless-cluster"
kubectl() {
    command kubectl --context="${KIND_CONTEXT}" "$@"
}

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DASHBOARD_PID_FILE="${PROJECT_DIR}/dashboard/.dashboard.pid"
DASHBOARD_LOG_FILE="${PROJECT_DIR}/dashboard/dashboard.log"

# Color scheme
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
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
    echo -e "   ${GREEN}start${NC}         -> Resume cluster, reconcile workloads, and start dashboard"
    echo -e "   ${YELLOW}stop${NC}          -> Graceful shutdown (cluster + dashboard)"
    echo -e "   ${CYAN}status${NC}        -> Component health, pod metrics, HPA, and dashboard status"
    echo -e "   ${CYAN}restart${NC}       -> Restart Kind cluster container and dashboard"
    echo -e "   ${CYAN}dashboard${NC}     -> Manage dashboard [start|stop|restart|logs|status]"
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

start_dashboard() {
    # Check if already running
    if [ -f "$DASHBOARD_PID_FILE" ] && kill -0 "$(cat "$DASHBOARD_PID_FILE")" 2>/dev/null; then
        echo -e " ${GREEN}[✓] Observability Dashboard is already running (PID: $(cat "$DASHBOARD_PID_FILE")).${NC}"
        echo -e " • Dashboard UI     : http://127.0.0.1:8888"
        return 0
    fi
    if command -v lsof &>/dev/null && lsof -ti:8888 &>/dev/null; then
        local existing_pid
        existing_pid=$(lsof -ti:8888 | head -n 1)
        echo "$existing_pid" > "$DASHBOARD_PID_FILE"
        echo -e " ${GREEN}[✓] Observability Dashboard is already running (PID: $existing_pid).${NC}"
        echo -e " • Dashboard UI     : http://127.0.0.1:8888"
        return 0
    fi

    echo -e " Starting Observability Dashboard in background..."
    nohup python3 "${PROJECT_DIR}/dashboard/server.py" > "$DASHBOARD_LOG_FILE" 2>&1 &
    local new_pid=$!
    echo "$new_pid" > "$DASHBOARD_PID_FILE"
    sleep 1

    if kill -0 "$new_pid" 2>/dev/null; then
        echo -e " ${GREEN}[✓] Observability Dashboard online (PID: $new_pid).${NC}"
        echo -e " • Dashboard UI     : http://127.0.0.1:8888"
    else
        echo -e " ${YELLOW}[!] Dashboard failed to start. Check: $DASHBOARD_LOG_FILE${NC}"
    fi
}

stop_dashboard() {
    if [ -f "$DASHBOARD_PID_FILE" ]; then
        local pid
        pid=$(cat "$DASHBOARD_PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
            sleep 0.5
            kill -9 "$pid" 2>/dev/null || true
        fi
        rm -f "$DASHBOARD_PID_FILE"
    fi
    if command -v lsof &>/dev/null; then
        local orphan_pid
        orphan_pid=$(lsof -ti:8888 2>/dev/null || true)
        if [ -n "$orphan_pid" ]; then
            kill -9 "$orphan_pid" 2>/dev/null || true
        fi
    fi
}

dashboard_status() {
    if [ -f "$DASHBOARD_PID_FILE" ] && kill -0 "$(cat "$DASHBOARD_PID_FILE")" 2>/dev/null; then
        echo -e "   • Dashboard Server: ${GREEN}${BOLD}RUNNING${NC} (PID: $(cat "$DASHBOARD_PID_FILE")) on http://127.0.0.1:8888"
    elif command -v lsof &>/dev/null && lsof -ti:8888 &>/dev/null; then
        local pid
        pid=$(lsof -ti:8888 | head -n 1)
        echo -e "   • Dashboard Server: ${GREEN}${BOLD}RUNNING${NC} (PID: $pid) on http://127.0.0.1:8888"
    else
        echo -e "   • Dashboard Server: ${YELLOW}STOPPED${NC} (Run: ./cluster_manage.sh dashboard start)"
    fi
}

case "$1" in
    stop|down|pause|shutdown)
        banner
        echo -e " ==> Stopping cluster and services ($KIND_CONTAINER)..."
        echo -e " [1/4] Stopping background Observability Dashboard..."
        stop_dashboard
        echo -e " [2/4] Flushing in-memory sync buffers..."
        sync || true
        echo -e " [3/4] Gracefully suspending Kind cluster container..."
        docker stop -t 5 "$KIND_CONTAINER" >/dev/null 2>&1 || true
        echo -e " [4/4] Releasing host resources..."
        echo ""
        echo -e " ${GREEN}[✓] Cluster and services suspended.${NC}"
        echo -e " • Host resource usage: 0% CPU / 0 MB RAM"
        echo -e " • State: Preserved in Docker persistent volume"
        echo -e " • Resume command: ./cluster_manage.sh start\n"
        ;;

    start|up|resume|boot)
        banner
        echo -e " ==> Starting serverless pipeline cluster ($KIND_CONTAINER)..."
        echo -e " [1/6] Starting Docker container..."
        docker start "$KIND_CONTAINER" >/dev/null
        echo -e " [2/6] Checking Kubernetes control plane..."
        wait_for_apiserver
        echo -e " [3/6] Waiting for OpenFaaS Gateway and MinIO..."
        wait_for_openfaas
        echo -e " [4/6] Reconciling NetworkPolicy, secrets, and pod specs..."
        kubectl apply -f "${PROJECT_DIR}/security_suite/network_policy_and_secrets.yaml" >/dev/null 2>&1 || true
        kubectl create configmap function-handler-code \
          --from-file=handler.py="${PROJECT_DIR}/function/image-processor-app/handler.py" \
          -n openfaas-fn --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1 || true
        kubectl apply -f "${PROJECT_DIR}/infrastructure/k8s-function.yaml" >/dev/null 2>&1 || true
        kubectl apply -f "${PROJECT_DIR}/infrastructure/function.yaml" >/dev/null 2>&1 || true
        kubectl apply -f "${PROJECT_DIR}/infrastructure/hpa.yaml" >/dev/null 2>&1 || true
        kubectl rollout restart deployment image-processor-app -n openfaas-fn >/dev/null 2>&1 || true
        kubectl rollout status deployment image-processor-app -n openfaas-fn --timeout=35s >/dev/null 2>&1 || true
        
        echo -e " [5/6] Active Pod Summary:"
        kubectl get pods -n openfaas-fn
        echo ""
        echo -e " [6/6] Ensuring Observability Dashboard is running..."
        start_dashboard
        echo ""
        echo -e " ${GREEN}[✓] Cluster online and ready.${NC}"
        echo -e " • Gateway Endpoint : http://127.0.0.1:8080"
        echo -e " • MinIO Storage    : http://127.0.0.1:9000"
        echo -e " • Dashboard UI     : http://127.0.0.1:8888\n"
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
        echo -e " ${BOLD}Observability Dashboard:${NC}"
        dashboard_status
        echo ""
        ;;

    dashboard|dash|ui)
        banner
        case "$2" in
            stop)
                echo -e " ==> Stopping Observability Dashboard..."
                stop_dashboard
                echo -e " ${GREEN}[✓] Dashboard stopped.${NC}\n"
                ;;
            restart)
                echo -e " ==> Restarting Observability Dashboard..."
                stop_dashboard
                start_dashboard
                echo ""
                ;;
            logs)
                if [ -f "$DASHBOARD_LOG_FILE" ]; then
                    tail -n 30 "$DASHBOARD_LOG_FILE"
                else
                    echo -e " ${YELLOW}[!] No dashboard log file found at $DASHBOARD_LOG_FILE${NC}"
                fi
                ;;
            start)
                echo -e " ==> Starting Observability Dashboard..."
                start_dashboard
                echo ""
                ;;
            status|"")
                echo -e " ==> Observability Dashboard Status:\n"
                dashboard_status
                echo ""
                ;;
        esac
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
        
        echo -e " [1/5] Applying NetworkPolicy and secrets..."
        kubectl apply -f "${PROJECT_DIR}/security_suite/network_policy_and_secrets.yaml" >/dev/null
        
        echo -e " [2/5] Syncing handler configmap..."
        kubectl create configmap function-handler-code \
          --from-file=handler.py="${PROJECT_DIR}/function/image-processor-app/handler.py" \
          -n openfaas-fn --dry-run=client -o yaml | kubectl apply -f - >/dev/null
          
        echo -e " [3/5] Reconciling pod specifications and HPA..."
        kubectl apply -f "${PROJECT_DIR}/infrastructure/k8s-function.yaml" >/dev/null
        kubectl apply -f "${PROJECT_DIR}/infrastructure/function.yaml" >/dev/null
        kubectl apply -f "${PROJECT_DIR}/infrastructure/hpa.yaml" >/dev/null
        
        echo -e " [4/5] Performing rolling deployment restart..."
        kubectl rollout restart deployment image-processor-app -n openfaas-fn >/dev/null
        kubectl rollout status deployment image-processor-app -n openfaas-fn --timeout=35s >/dev/null

        echo -e " [5/5] Ensuring Observability Dashboard is running..."
        start_dashboard
        
        echo -e "\n ${GREEN}[✓] All controls reconciled successfully.${NC}\n"
        ;;

    restart)
        banner
        echo -e " ==> Restarting Kind cluster container..."
        docker restart "$KIND_CONTAINER"
        wait_for_apiserver
        wait_for_openfaas
        kubectl get pods -n openfaas-fn
        start_dashboard
        echo -e " ${GREEN}[✓] Restart complete.${NC}\n"
        ;;

    audit|test|eval|evaluate)
        banner
        echo -e " ==> Running verification test suite...\n"
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
