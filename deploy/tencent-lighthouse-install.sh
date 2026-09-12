#!/usr/bin/env bash
set -euo pipefail

DOMAIN="api.jiatuc.cn"
APP_DIR="/opt/new-api"

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is not installed. Install Docker first, then rerun this script." >&2
  exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "Docker Compose v2 is not available. Install Docker Compose first, then rerun this script." >&2
  exit 1
fi

sudo mkdir -p "${APP_DIR}"
sudo chown -R "${USER}:${USER}" "${APP_DIR}"
cd "${APP_DIR}"

POSTGRES_PASSWORD="$(openssl rand -hex 32)"
REDIS_PASSWORD="$(openssl rand -hex 32)"
SESSION_SECRET="$(openssl rand -hex 32)"
CRYPTO_SECRET="$(openssl rand -hex 32)"

cat > .env <<EOF
TZ=Asia/Shanghai
NEW_API_PORT=127.0.0.1:3000
FRONTEND_BASE_URL=https://${DOMAIN}
NEW_API_DOMAIN=${DOMAIN}

POSTGRES_USER=newapi
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=new-api

REDIS_PASSWORD=${REDIS_PASSWORD}

SESSION_SECRET=${SESSION_SECRET}
CRYPTO_SECRET=${CRYPTO_SECRET}

ERROR_LOG_ENABLED=true
BATCH_UPDATE_ENABLED=true
NODE_NAME=new-api-node-1
STREAMING_TIMEOUT=300
RELAY_IDLE_CONN_TIMEOUT=90
EOF

cat > Caddyfile <<EOF
${DOMAIN} {
	encode gzip
	reverse_proxy new-api:3000
}
EOF

cat > docker-compose.yml <<'EOF'
services:
  new-api:
    image: calciumion/new-api:latest
    container_name: new-api
    restart: always
    command: --log-dir /app/logs
    ports:
      - "${NEW_API_PORT:-127.0.0.1:3000}:3000"
    volumes:
      - ./data:/data
      - ./logs:/app/logs
    environment:
      SQL_DSN: "postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}"
      REDIS_CONN_STRING: "redis://:${REDIS_PASSWORD}@redis:6379"
      TZ: "${TZ:-Asia/Shanghai}"
      FRONTEND_BASE_URL: "${FRONTEND_BASE_URL}"
      SESSION_SECRET: "${SESSION_SECRET}"
      CRYPTO_SECRET: "${CRYPTO_SECRET}"
      ERROR_LOG_ENABLED: "${ERROR_LOG_ENABLED:-true}"
      BATCH_UPDATE_ENABLED: "${BATCH_UPDATE_ENABLED:-true}"
      NODE_NAME: "${NODE_NAME:-new-api-node-1}"
      STREAMING_TIMEOUT: "${STREAMING_TIMEOUT:-300}"
      RELAY_IDLE_CONN_TIMEOUT: "${RELAY_IDLE_CONN_TIMEOUT:-90}"
    depends_on:
      redis:
        condition: service_started
      postgres:
        condition: service_healthy
    networks:
      - new-api-network
    healthcheck:
      test: ["CMD-SHELL", "wget -q -O - http://localhost:3000/api/status | grep -Eq '\"success\"[[:space:]]*:[[:space:]]*true' || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3

  caddy:
    image: caddy:2-alpine
    container_name: new-api-caddy
    restart: always
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy_data:/data
      - caddy_config:/config
    depends_on:
      new-api:
        condition: service_started
    networks:
      - new-api-network

  redis:
    image: redis:7-alpine
    container_name: redis
    restart: always
    command: ["redis-server", "--requirepass", "${REDIS_PASSWORD}"]
    volumes:
      - redis_data:/data
    networks:
      - new-api-network

  postgres:
    image: postgres:15
    container_name: postgres
    restart: always
    environment:
      POSTGRES_USER: "${POSTGRES_USER}"
      POSTGRES_PASSWORD: "${POSTGRES_PASSWORD}"
      POSTGRES_DB: "${POSTGRES_DB}"
    volumes:
      - pg_data:/var/lib/postgresql/data
    networks:
      - new-api-network
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5

volumes:
  pg_data:
  redis_data:
  caddy_data:
  caddy_config:

networks:
  new-api-network:
    driver: bridge
EOF

echo "Pulling images..."
docker compose pull

echo "Starting New API stack..."
docker compose up -d

echo "Waiting for services..."
sleep 10

docker compose ps

echo "New API recent logs:"
docker compose logs --tail=80 new-api

echo "Local health check:"
curl -fsS http://127.0.0.1:3000/api/status || true
echo

echo "Listening ports:"
sudo ss -lntp | grep -E ':(22|80|443|3000|5432|6379)\b' || true

echo "Done. If ports 80/443 are open in Tencent Cloud firewall, test: https://${DOMAIN}"


