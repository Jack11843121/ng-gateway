#!/usr/bin/env bash
# =============================================================================
# NG 网关 一键安装脚本（在客户的 Linux 主机直接运行）
#   流程：装 Docker → 从腾讯云下载「预构建镜像包 + docker-compose.yml」
#         → docker load 加载镜像 → docker compose 启动 data-plane + control-plane + etcd
#   客户机无需 Go / OpenResty / etcd，也无需编译源码。
#
# 用法：  sudo bash ng-gateway-install.sh
# 可覆盖：VERSION（默认 1.0.0） BASE_URL（默认腾讯云） DOCKER_MIRROR（国内加速）
# =============================================================================
set -euo pipefail

VERSION="${VERSION:-1.0.0}"
BASE_URL="${BASE_URL:-http://140.143.248.224:8000/releases}"

info() { echo -e "\033[36m==>\033[0m $*"; }
ok()   { echo -e "\033[32m>> $*\033[0m"; }
err()  { echo -e "\033[31m!! $*\033[0m" >&2; }

# 1) 安装 Docker ---------------------------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
  info "未检测到 Docker，正在安装 ..."
  curl -fsSL https://get.docker.com | bash -s docker --mirror Aliyun \
    || wget -qO- https://get.docker.com | bash -s docker --mirror Aliyun
  systemctl enable --now docker 2>/dev/null || service docker start 2>/dev/null || true
fi

if docker compose version >/dev/null 2>&1; then COMPOSE="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then COMPOSE="docker-compose"
else err "未找到 docker compose / docker-compose，请升级 Docker"; exit 1; fi

if [ -n "${DOCKER_MIRROR:-}" ]; then
  mkdir -p /etc/docker
  echo "{ \"registry-mirrors\": [\"$DOCKER_MIRROR\"] }" > /etc/docker/daemon.json
  systemctl restart docker 2>/dev/null || service docker restart 2>/dev/null || true
fi

# 2) 从腾讯云下载必要资源 ------------------------------------------------------
cd "$(dirname "$0")"
info "从腾讯云下载 NG 网关预构建镜像包（v${VERSION}）与编排文件 ..."
curl -fSL --retry 3 "$BASE_URL/ng-gateway-images-${VERSION}.tar.gz" -o "ng-gateway-images-${VERSION}.tar.gz"
curl -fSL --retry 3 "$BASE_URL/ng-gateway-compose.yml" -o docker-compose.yml

# 3) 加载镜像 + 启动 -----------------------------------------------------------
info "加载镜像（data-plane + control-plane）..."
gunzip -c "ng-gateway-images-${VERSION}.tar.gz" | docker load
info "启动 NG 网关（etcd + 数据面 + 控制面）..."
$COMPOSE up -d

for i in $(seq 1 60); do
  if curl -fsS "http://127.0.0.1:8081/healthz" >/dev/null 2>&1; then
    ok "✅ NG 网关控制面已启动！"; break
  fi
  sleep 3
done

cat <<EOF

========================================================
  🚀 NG 网关（GatewayMaster 系列）安装完成
--------------------------------------------------------
  网关数据面     http://<服务器IP>:8080
  Prometheus     http://<服务器IP>:9091/metrics
  管理端 Admin API http://<服务器IP>:8081/api/v1/config

  下一步：通过 Admin API 创建上游与路由：
    curl -X POST http://<服务器IP>:8081/api/v1/upstreams -d '{"id":"up1","nodes":[{"host":"10.0.0.3","port":8080}]}'
    curl -X POST http://<服务器IP>:8081/api/v1/routes    -d '{"id":"r1","uri":"/","upstream_id":"up1","plugins":[]}'
========================================================
EOF

info "已下载的镜像包可删除：rm -f ng-gateway-images-${VERSION}.tar.gz"