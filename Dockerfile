# DeepSeek Harness fnOS 镜像（x86_64）
# 基础镜像使用官方多架构 Node 22（满足 dsh 要求的 ^22.19 || >=24）
FROM node:22-bookworm-slim

# 锁定的 dsh 版本，升级时改这里即可（预览版迭代快，建议固定）
ARG DSH_VERSION=0.1.0-rc.6
ENV DSH_VERSION=${DSH_VERSION}

RUN apt-get update \
 && apt-get install -y --no-install-recommends socat ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# 把 dsh CLI（含 Web UI）烤进镜像，避免运行时下载
RUN npm install -g @deepseek-ai/dsh@${DSH_VERSION}

WORKDIR /workspace

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 3080

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
