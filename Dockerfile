# DeepSeek Harness fnOS 镜像（x86_64）
# 基础镜像使用官方多架构 Node 22（满足 dsh 要求的 ^22.19 || >=24）
FROM node:22-bookworm-slim

# 锁定的 dsh 版本，升级时改这里即可（预览版迭代快，建议固定）
ARG DSH_VERSION=0.1.0-rc.6
ENV DSH_VERSION=${DSH_VERSION}

# ca-certificates: 拉 GHCR/网络所需
# python3/make/g++/pkg-config: dsh 依赖 node-pty 原生模块，slim 镜像缺编译工具，必须补上才能 npm install
# 反代改用镜像自带的 Node 代理 proxy.js，不再需要 socat
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates python3 make g++ pkg-config \
 && rm -rf /var/lib/apt/lists/*

# 把 dsh CLI（含 Web UI）烤进镜像，避免运行时下载
# node-pty 需编译，故先装好上面的工具链；编译产物保留在镜像内即可
RUN npm install -g @deepseek-ai/dsh@${DSH_VERSION}

WORKDIR /workspace

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY proxy.js /usr/local/bin/proxy.js
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 3080

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
