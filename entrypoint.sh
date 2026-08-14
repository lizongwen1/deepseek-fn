#!/bin/sh
# dsh web 默认只监听 127.0.0.1:3080，用 socat 反代到 0.0.0.0:3080 让飞牛外部可访问。
# 注意：本镜像的 /bin/sh 是 dash（Debian 系默认），不能使用 bash 专属的 `wait -n`，
# 改用 POSIX 兼容的轮询 `kill -0` 来监控两个后台进程。
set -e

cd /workspace

dsh web &
DSH_PID=$!

socat TCP-LISTEN:3080,fork,reuseaddr,bind=0.0.0.0 TCP:127.0.0.1:3080 &
SOCAT_PID=$!

# 监控两个进程：任一退出则整体退出（纯 POSIX sh，兼容 dash/bash）
while kill -0 "$DSH_PID" 2>/dev/null && kill -0 "$SOCAT_PID" 2>/dev/null; do
  sleep 1
done

# 清理剩余进程
kill -TERM "$DSH_PID" "$SOCAT_PID" 2>/dev/null || true
exit 1
