#!/bin/bash
# 本地构建 .fpk（可选）：先把镜像构建/推送到你的 GHCR，再用 fnpack 出包
# 仓库根目录即应用目录，故 --directory 用 . ，compose 相对路径为 app/docker/
set -e

REPO_OWNER=${REPO_OWNER:-your-github-username}
GHCR_IMAGE=${GHCR_IMAGE:-ghcr.io/${REPO_OWNER}/deepseek-harness-fnos:latest}

echo "使用镜像地址: $GHCR_IMAGE"

# 1) 替换 compose 里的占位符
sed -i "s#__GHCR_IMAGE__#$GHCR_IMAGE#g" app/docker/docker-compose.yaml

# 2) （可选）本地构建并推送镜像
# docker build -t "$GHCR_IMAGE" .
# docker push "$GHCR_IMAGE"

# 3) 下载 fnpack (1.2.1 支持 platform=all，且要求 cmd/install_init) 并出包
curl -#kL https://static2.fnnas.com/fnpack/fnpack-1.2.1-linux-amd64 -o fnpack
chmod +x fnpack
chmod +x cmd/main cmd/install_init cmd/install_callback \
  cmd/uninstall_init cmd/uninstall_callback \
  cmd/upgrade_init cmd/upgrade_callback \
  cmd/config_init cmd/config_callback
./fnpack build --directory .

echo "产出: deepseek-harness.fpk"
