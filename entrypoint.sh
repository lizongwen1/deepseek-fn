#!/bin/sh
# dsh web 默认只监听 127.0.0.1:3080（官方刻意 local-first，拒绝 --host 0.0.0.0）。
# 用 socat 反代：socat 监听 0.0.0.0:3081，转发给 dsh 的 127.0.0.1:3080。
# 关键：socat 与 dsh 用【不同端口】，避免两者抢 127.0.0.1:3080 导致
#       EADDRINUSE 崩溃循环（之前 socat 绑 0.0.0.0:3080 会把回环 3080 一起占掉）。
# compose 把宿主机 service_port(3080) 映射到容器 3081，外部照常访问 3080。
# 注意：本镜像 /bin/sh 是 dash，不能用 bash 专属的 `wait -n`，用 POSIX 轮询 kill -0。
set -e

cd /workspace

dsh web &
DSH_PID=$!

socat TCP-LISTEN:3081,fork,reuseaddr,bind=0.0.0.0 TCP:127.0.0.1:3080 &
SOCAT_PID=$!

# 监控两个进程：任一退出则整体退出（纯 POSIX sh，兼容 dash/bash）
while kill -0 "$DSH_PID" 2>/dev/null && kill -0 "$SOCAT_PID" 2>/dev/null; do
  sleep 1
done

# 清理剩余进程
kill -TERM "$DSH_PID" "$SOCAT_PID" 2>/dev/null || true
exit 1
