#!/bin/sh
# dsh web 默认只监听 127.0.0.1:3080，用 socat 反代到 0.0.0.0:3080 让飞牛外部可访问
set -e

cd /workspace

dsh web &
DSH_PID=$!

socat TCP-LISTEN:3080,fork,reuseaddr,bind=0.0.0.0 TCP:127.0.0.1:3080 &
SOCAT_PID=$!

# 任一进程退出则整体退出
wait -n
kill -TERM "$DSH_PID" "$SOCAT_PID" 2>/dev/null || true
