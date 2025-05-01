#!/usr/bin/env bash
set -euo pipefail

CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

echo -e "${CYAN}${BOLD}"
echo "-----------------------------------------------------"
echo "   Aztec Node Install"
echo "-----------------------------------------------------"
echo ""

# ====================================================
# Tự động cài đặt và khởi động node đầy đủ Aztec alpha-testnet
# Phiên bản: v0.85.0-alpha-testnet.5
# Chỉ dành cho Ubuntu/Debian, yêu cầu quyền sudo
# ====================================================

if [ "$(id -u)" -ne 0 ]; then
  echo "⚠️ Vui lòng chạy script này với quyền root (hoặc sudo)."
  exit 1
fi

if ! command -v docker &> /dev/null || ! command -v docker-compose &> /dev/null; then
  echo "[+] Docker hoặc Docker Compose chưa được cài đặt. Đang cài đặt..."
  apt-get update
  apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg-agent \
    software-properties-common
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
  add-apt-repository \
    "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable"
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io
  curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" \
    -o /usr/local/bin/docker-compose
  chmod +x /usr/local/bin/docker-compose
else
  echo "[+] Docker và Docker Compose đã được cài đặt."
fi

if ! command -v node &> /dev/null; then
  echo "[+] Node.js chưa được cài đặt. Đang cài đặt phiên bản mới nhất..."
  curl -fsSL https://deb.nodesource.com/setup_current.x | sudo -E bash -
  apt-get install -y nodejs
else
  echo "[+] Node.js đã được cài đặt."
fi

echo "[+] Đang cài đặt Aztec CLI và chuẩn bị alpha-testnet..."
curl -sL https://install.aztec.network | bash

export PATH="$HOME/.aztec/bin:$PATH"

if ! command -v aztec-up &> /dev/null; then
  echo "[-] Cài đặt Aztec CLI thất bại."
  exit 1
fi

aztec-up alpha-testnet

echo -e "\n[i] Hướng dẫn lấy RPC URLs:"
echo "  - L1 Execution Client (EL) RPC URL:"
echo "    1. Đăng ký hoặc đăng nhập tại https://dashboard.alchemy.com/"
echo "    2. Tạo ứng dụng mới cho testnet Sepolia"
echo "    3. Sao chép URL HTTPS (ví dụ: https://eth-sepolia.g.alchemy.com/v2/<your-key>)"
echo ""
echo "  - L1 Consensus (CL) RPC URL:"
echo "    1. Đăng ký hoặc đăng nhập tại https://drpc.org/"
echo "    2. Tạo API key cho testnet Sepolia"
echo "    3. Sao chép URL HTTPS (ví dụ: https://lb.drpc.org/ogrpc?network=sepolia&dkey=<your-key>)"
echo ""

read -p "[>] Nhập L1 Execution Client (EL) RPC URL: " ETH_RPC
read -p "[>] Nhập L1 Consensus (CL) RPC URL: " CONS_RPC
read -p "[>] Nhập Blob Sink URL (bỏ qua nếu không có): " BLOB_URL
read -p "[>] Nhập Validator Private Key: " VALIDATOR_PRIVATE_KEY

echo "[+] Đang lấy địa chỉ IP công cộng..."
PUBLIC_IP=$(curl -s ifconfig.me || echo "127.0.0.1")
echo "    → $PUBLIC_IP"

cat > .env <<EOF
ETHEREUM_HOSTS="$ETH_RPC"
L1_CONSENSUS_HOST_URLS="$CONS_RPC"
P2P_IP="$PUBLIC_IP"
VALIDATOR_PRIVATE_KEY="$VALIDATOR_PRIVATE_KEY"
DATA_DIRECTORY="/data"
LOG_LEVEL="debug"
EOF

if [ -n "$BLOB_URL" ]; then
  echo "BLOB_SINK_URL=\"$BLOB_URL\"" >> .env
fi

BLOB_FLAG=""
if [ -n "$BLOB_URL" ]; then
  BLOB_FLAG="--sequencer.blobSinkUrl \$BLOB_SINK_URL"
fi

cat > docker-compose.yml <<EOF
version: "3.8"
services:
  node:
    image: aztecprotocol/aztec:0.85.0-alpha-testnet.5
    network_mode: host
    environment:
      - ETHEREUM_HOSTS=\${ETHEREUM_HOSTS}
      - L1_CONSENSUS_HOST_URLS=\${L1_CONSENSUS_HOST_URLS}
      - P2P_IP=\${P2P_IP}
      - VALIDATOR_PRIVATE_KEY=\${VALIDATOR_PRIVATE_KEY}
      - DATA_DIRECTORY=\${DATA_DIRECTORY}
      - LOG_LEVEL=\${LOG_LEVEL}
      - BLOB_SINK_URL=\${BLOB_SINK_URL:-}
    entrypoint: >
      sh -c 'node --no-warnings /usr/src/yarn-project/aztec/dest/bin/index.js start --network alpha-testnet --node --archiver --sequencer $BLOB_FLAG'
    volumes:
      - $(pwd)/data:/data
EOF

mkdir -p data

echo "[+] Khởi động Aztec full node (docker-compose up -d)..."
docker-compose up -d

echo -e "\n[✔] Cài đặt và khởi động hoàn tất!"
echo "   - Xem logs: docker-compose logs -f"
echo "   - Thư mục dữ liệu: $(pwd)/data"
