#!/usr/bin/env bash
set -euo pipefail

CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

echo -e "${CYAN}${BOLD}"
echo "-----------------------------------------------------"
echo "   Aztec install"
echo "-----------------------------------------------------"
echo ""

# Kiểm tra Docker và Docker Compose
if ! command -v docker &> /dev/null || ! command -v docker-compose &> /dev/null; then
  echo "[+] Docker hoặc Docker Compose chưa được cài đặt. Vui lòng cài đặt trước khi chạy script."
  exit 1
else
  echo "[+] Docker và Docker Compose đã được cài đặt."
fi

# Kiểm tra Node.js
if ! command -v node &> /dev/null; then
  echo "[+] Node.js chưa được cài đặt. Đang cài đặt bằng nvm..."
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
  export NVM_DIR="$HOME/.nvm"
  [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
  nvm install node
else
  echo "[+] Node.js đã được cài đặt."
fi

# Cài đặt Aztec CLI
echo "[+] Đang cài đặt Aztec CLI và chuẩn bị alpha-testnet..."
curl -sL https://install.aztec.network | bash

export PATH="$HOME/.aztec/bin:$PATH"

if ! command -v aztec-up &> /dev/null; then
  echo "[-] Cài đặt Aztec CLI thất bại."
  exit 1
fi

aztec-up alpha-testnet

# Yêu cầu người dùng nhập thông tin
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

# Lấy IP công cộng
echo "[+] Đang lấy địa chỉ IP công cộng..."
PUBLIC_IP=$(curl -s ifconfig.me || echo "127.0.0.1")
echo "    → $PUBLIC_IP"

# Tạo file .env
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

# Tạo file docker-compose.yml
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

# Khởi động node
echo "[+] Khởi động Aztec full node (docker-compose up -d)..."
docker-compose up -d

echo -e "\n[✔] Cài đặt và khởi động hoàn tất!"
echo "   - Xem logs: docker-compose logs -f"
echo "   - Thư mục dữ liệu: $(pwd)/data"
