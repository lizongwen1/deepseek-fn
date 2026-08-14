#!/bin/sh
# dsh web 默认只监听 127.0.0.1:3080（官方刻意 local-first，拒绝 --host 0.0.0.0）。
# 用 Node 反向代理 proxy.js 反代：监听 0.0.0.0:3081，转发给 dsh 的 127.0.0.1:3080。
# 代理额外做两件事：① 删除 X-Frame-Options/CSP，让飞牛 iframe 能嵌入（修白屏）
#                     ② 给 HTML 注入 crypto.randomUUID / AbortSignal.timeout / AbortSignal.any 的 polyfill（修旧 webview 报错）
#                     ③ 把转发给 dsh 的 Host/Origin 改写成 127.0.0.1:3080，绕过 dsh 的 browser-trust 围栏（修 host.listDirectory 403）
# compose 把宿主机 service_port(3080) 映射到容器 3081，外部照常访问 3080。
# 注意：本镜像 /bin/sh 是 dash，不能用 bash 专属的 `wait -n`，用 POSIX 轮询 kill -0。
set -e

cd /workspace

dsh web &
DSH_PID=$!

node /usr/local/bin/proxy.js &
PROXY_PID=$!

# 监控两个进程：任一退出则整体退出（纯 POSIX sh，兼容 dash/bash）
while kill -0 "$DSH_PID" 2>/dev/null && kill -0 "$PROXY_PID" 2>/dev/null; do
  sleep 1
done

# 清理剩余进程
kill -TERM "$DSH_PID" "$PROXY_PID" 2>/dev/null || true
exit 1
