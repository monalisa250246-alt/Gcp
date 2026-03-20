#!/usr/bin/env bash
set -euo pipefail

# Fix interactive
if [[ ! -t 0 ]] && [[ -e /dev/tty ]]; then
  exec </dev/tty
fi

LOG_FILE="/tmp/vless_$(date +%s).log"
touch "$LOG_FILE"

trap 'echo "ERROR at line $LINENO"; exit 1' ERR

# Color
GREEN="\e[32m"
RED="\e[31m"
CYAN="\e[36m"
RESET="\e[0m"

clear
echo -e "${CYAN}VLESS Cloud Run Auto Deploy${RESET}"
echo "----------------------------------"

# Telegram
read -rp "Telegram Bot Token (skip = enter): " TG_TOKEN || true
read -rp "Chat ID (skip = enter): " TG_CHAT || true

tg_send() {
  local msg="$1"
  if [[ -n "${TG_TOKEN:-}" && -n "${TG_CHAT:-}" ]]; then
    curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
      -d "chat_id=${TG_CHAT}" \
      --data-urlencode "text=${msg}" >/dev/null 2>&1
  fi
}

# Project
PROJECT=$(gcloud config get-value project 2>/dev/null || true)

if [[ -z "$PROJECT" ]]; then
  echo -e "${RED}No GCP Project${RESET}"
  echo "Run: gcloud config set project YOUR_PROJECT"
  exit 1
fi

PROJECT_NUMBER=$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')
echo -e "${GREEN}Project:${RESET} $PROJECT"

# Config
read -rp "Region (default us-central1): " REGION || true
REGION=${REGION:-us-central1}

read -rp "Service Name (default vless-auto): " SERVICE || true
SERVICE=${SERVICE:-vless-auto}

IMAGE="docker.io/priknon/vless-ws:latest"

# Enable API
echo "Enabling APIs..."
gcloud services enable run.googleapis.com cloudbuild.googleapis.com --quiet

# Deploy
echo "Deploying..."

gcloud run deploy "$SERVICE" \
  --image="$IMAGE" \
  --platform=managed \
  --region="$REGION" \
  --allow-unauthenticated \
  --memory=2Gi \
  --cpu=2 \
  --port=8080 \
  --quiet

# Generate config
HOST="${SERVICE}-${PROJECT_NUMBER}.${REGION}.run.app"
URL="https://${HOST}"

UUID=$(cat /proc/sys/kernel/random/uuid)
PATH_WS=$(tr -dc a-z0-9 </dev/urandom | head -c 8)

URI="vless://${UUID}@vpn.googleapis.com:443?type=ws&security=tls&host=${HOST}&path=%2F${PATH_WS}&sni=${HOST}#VLESS-GCP"

# Output
echo ""
echo -e "${GREEN}DEPLOY SUCCESS${RESET}"
echo "URL: $URL"
echo ""
echo "VLESS:"
echo "$URI"

QR="https://api.qrserver.com/v1/create-qr-code/?size=300x300&data=${URI}"
echo ""
echo "QR:"
echo "$QR"

# Telegram
MSG="VLESS Deploy Success
Region: $REGION
URL: $URL

$URI"

tg_send "$MSG"

echo ""
echo -e "${GREEN}DONE${RESET}"
