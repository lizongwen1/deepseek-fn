#!/bin/bash
# 本地构建 .fpk（可选）：先把镜像构建/推送到你的 GHCR，再用 fnpack 出包
set -e

REPO_OWNER=${REPO_OWNER:-your-github-username}
GHCR_IMAGE=${GHCR_IMAGE:-ghcr.io/${REPO_OWNER}/deepseek-harness-fnos:latest}

echo "使用镜像地址: $GHCR_IMAGE"

# 1) 替换 compose 里的占位符
sed -i "s#__GHCR_IMAGE__#$GHCR_IMAGE#g" deepseek-harness-fnos/app/docker/docker-compose.yaml

# 2) （可选）本地构建并推送镜像
# docker build -t "$GHCR_IMAGE" .
# docker push "$GHCR_IMAGE"

# 3) 下载 fnpack 并出包
curl -#kL https://static2.fnnas.com/fnpack/fnpack-1.0.4-linux-amd64 -o fnpack
chmod +x fnpack
./fnpack build --directory deepseek-harness-fnos

echo "产出: deepseek-harness.fpk"
