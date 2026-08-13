# DeepSeek Harness for fnOS（飞牛）

把 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)（一切皆插件的开源 Agent 运行时）打包成飞牛 fnOS 第三方应用，安装方式类似 Lucky：在「应用中心 → 手动安装」上传 `.fpk` 即可。

> 状态：基于 v0.1 开发者预览（2026-08-13 开源，MIT）。预览版迭代快、可能有破坏性变更，**已固定 dsh 版本**，升级改 Dockerfile 里的 `DSH_VERSION` 即可。

## 架构

- 一个 Docker 镜像（基于 `node:22-bookworm-slim`，含全局安装的 `dsh`），推送到 GHCR。
- 飞牛应用中心用官方 `fnpack` 把本仓库目录结构打成 `.fpk`。
- 容器内 `dsh web` 默认只监听 `127.0.0.1:3080`，用 `socat` 反代到 `0.0.0.0:3080`，保证飞牛外部（浏览器/桌面入口）可访问。
- 仅支持 **x86_64**（manifest `platform=x86`）；如需 ARM 版，改 manifest 与 CI 的 `platforms` 即可。

## 数据持久化

| 容器内路径 | 来源 | 用途 |
|---|---|---|
| `/root/.local/share/dsh` | `${TRIM_PKGVAR}/data` | 会话、配置、Trajectory 日志 |
| `/workspace` | `${TRIM_PKGVAR}/workspace` | Agent 默认工作目录（可在 Web UI 切换） |

## 使用 GitHub Actions 自动出包（推荐）

1. 把本仓库 fork / 推到你自己的 GitHub 账号下（repo 名建议 `deepseek-harness-fnos`）。
2. 在仓库 **Settings → Actions → General** 确认工作流有写包权限（默认 `GITHUB_TOKEN` 已开启 `packages: write`）。
3. 进入 **Actions → Build Image & FPK → Run workflow**。
   - 该流程会：构建 amd64 镜像并推送到 `ghcr.io/<你的用户名>/deepseek-harness-fnos:latest`，下载官方 `fnpack` 打出 `deepseek-harness.fpk` 作为 Artifact。
4. 下载 Artifact 里的 `deepseek-harness.fpk`，到飞牛「应用中心 → 手动安装」上传。
5. 安装后在桌面打开 **DeepSeek Harness**，在 **Settings → Models** 填 API Key（安装向导里填的 Key 也会以环境变量注入；二者任选其一）。

> 想发 Release 版本：给仓库打 `vX.Y.Z` 标签推送，Action 会自动把 `.fpk` 上传到 GitHub Release。

## 本地出包（可选）

```bash
# 设置你的 GitHub 用户名（用于镜像地址）
export REPO_OWNER=your-github-username
bash scripts/build-fpk.sh
# 产出 deepseek-harness.fpk
```

## 升级

1. 改 `Dockerfile` 的 `ARG DSH_VERSION`（例如 `0.1.0-rc.7`）。
2. 重新跑 Action / 本地构建，得到新的 `.fpk`。
3. 飞牛里「更新」该应用，上传新 `.fpk`。

## 常见问题

- **打不开页面**：确认 `manifest.service_port`、`docker-compose` 端口映射、`app/ui/config` 的 `port` 都是 `3080`；确认容器状态为 running。
- **模型连不上**：在 Web UI 的 Settings → Models 检查 Key / 端点；dsh 支持 DeepSeek 及 OpenAI 兼容端点。
- **代码沙箱/权限**：预览版含本地执行工具（bash/file-edit 等），默认在容器内以 root 运行，请注意工作目录与权限边界。
