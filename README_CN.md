# rust-dev-docker

[![Build and Push Docker Image](https://github.com/wzh19960613/rust-dev-docker/actions/workflows/docker.yml/badge.svg)](https://github.com/wzh19960613/rust-dev-docker/actions/workflows/docker.yml)

用于 Rust 开发的多架构（amd64 + arm64）Docker 镜像，可选集成 AI 编程助手、Node.js、Zsh、Python 等工具链。

English documentation: [README.md](./README.md)

---

## 预构建镜像

通过 GitHub Actions 自动构建多架构镜像，发布到 GitHub Container Registry：

**`ghcr.io/wzh19960613/rust-dev:latest`**

- 架构：`linux/amd64`、`linux/arm64`（Docker 自动选择）
- 每次 push 到 `main` 分支触发重新构建

### 拉取

```bash
# 公共镜像，直接拉取
docker pull ghcr.io/wzh19960613/rust-dev:latest
```

### 运行

```bash
# 准备 secrets（SSH 密码 + 可选的智谱 API Key）
mkdir -p ./secrets
echo "你的SSH密码" > ./secrets/ssh_password
echo "你的智谱API_Key" > ./secrets/zp_key   # 可选

# 启动容器
docker run -d \
  -p 2222:22 \
  -v "$PWD/secrets:/run/secrets:ro" \
  -v rust-dev-data:/root/workspace \
  ghcr.io/wzh19960613/rust-dev:latest

# 通过 SSH 连接
ssh -p 2222 root@localhost
```

---

## 镜像内容

基于官方 `rust:latest` 镜像，预装以下工具：

- **Rust 工具链**：`rustc`、`cargo`、`rustfmt`、`clippy`、`rust-analyzer`
- **SSH 服务**：已开启密码登录，通过挂载的 secret 文件配置
- **Node.js**：通过 NodeSource 安装（默认最新 LTS）
- **Zsh**：设为 root 用户的默认登录 shell（SSH 登录直接进 zsh）
- **Python 3**：含 `pip` 和 `venv`
- **AI 编程工具**（构建时可选）：Claude Code、OpenCode、Codex

所有工具都可通过构建参数开关或锁定版本（见下文）。

---

## 构建配置

Dockerfile 接受多个构建参数。其中 `NODE`、`ZSH`、`PYTHON` 三个参数共用统一的"三态"语义：

| 取值 | 含义 |
|---|---|
| `false` | 不安装 |
| `true` | 安装最新版本 |
| `<版本字符串>` | 安装指定版本 |

### 构建参数一览

| 参数 | 默认值 | 说明 |
|---|---|---|
| `RUST_TAG` | `latest` | 基础 `rust` 镜像的 tag |
| `SSH` | `true` | 安装并启用 SSH 服务 |
| `NODE` | `true` | Node.js：`true` / `false` / `22` / `22.5.0` |
| `ZSH` | `true` | Zsh：`true` / `false` / `5.9`（apt 版本约束） |
| `PYTHON` | `true` | Python：`true` / `false` / `3.11` |
| `CLAUDE_CODE` | `false` | 安装 Claude Code |
| `CODEX` | `false` | 安装 OpenAI Codex |
| `OPENCODE` | `false` | 安装 OpenCode + oh-my-opencode |
| `APT_MIRROR` | _(空)_ | 如 `https://mirrors.tuna.tsinghua.edu.cn` |
| `BUILD_PROXY` | _(空)_ | 构建过程使用的 HTTP/HTTPS/All 代理 |
| `GIT_USER` | _(空)_ | `git config --global user.name` |
| `GIT_EMAIL` | _(空)_ | `git config --global user.email` |

### 示例

```bash
# 默认配置：含 SSH + Node + Zsh + Python 的完整镜像
docker build -t rust-dev .

# 锁定指定版本
docker build \
  --build-arg NODE=22 \
  --build-arg ZSH=5.9 \
  --build-arg PYTHON=3.11 \
  -t rust-dev:custom .

# 最小化：仅 Rust，无任何附加工具
docker build --build-arg NODE=false --build-arg ZSH=false --build-arg PYTHON=false -t rust-dev:slim .

# 走代理 + 清华 apt 镜像
docker build \
  --build-arg BUILD_PROXY=http://your-proxy:port \
  --build-arg APT_MIRROR=https://mirrors.tuna.tsinghua.edu.cn \
  -t rust-dev .
```

---

## 从源码构建

### 使用 Make

```bash
cp .arg.example .arg       # 按需修改各项值
make init-secrets          # 用占位符创建 ./secrets 目录
make build                 # 构建镜像
make run                   # 运行容器
make ssh                   # SSH 进入运行中的容器
```

其他 Make 目标：`stop`、`rm`、`clean`、`shell`。

### 使用容器辅助脚本

`container.sh` 可创建带持久化卷的命名容器，并能把项目目录初始导入到 `/root/workspace`：

```bash
./container.sh --dir /path/to/your/project --ssh 2222
./container.sh --name my-dev --ssh 2223
./container.sh --base-name                  # 名字固定为 "rust-dev"
```

支持的选项：`--dir/-d`、`--name/-n`、`--full-name/-f`、`--base-name`、`--ssh/-s`、`--proxy/-p`、`--volume/-v`。

---

## Secrets（敏感信息）

Secrets 通过挂载到 `/run/secrets`（只读）的文件读取。支持两个文件：

| 文件 | 是否必需 | 用途 |
|---|---|---|
| `ssh_password` | 启用 SSH 时必需 | 设置 root 的 SSH 登录密码 |
| `zp_key` | 否 | 智谱 AI Key，用于 AI 助手鉴权 |

占位示例见 [`secrets.example/`](./secrets.example)。**切勿提交真实 secrets**——`secrets/` 目录已被 gitignore。

启动时 `entrypoint.sh` 会：

1. 自动选择 `npx`（已装 Node）或 `bunx` 作为 JS 运行时，可用 `-e USE_NODE=false` 覆盖
2. 完成智谱鉴权，并在已安装时 reload Claude Code / OpenCode
3. 启动 SSH 服务

---

## 升级已有容器

`update.sh` 会重建镜像并重建所有使用该镜像的容器，保留容器名、端口、卷、环境变量：

```bash
./update.sh --build         # 重建镜像 + 升级所有容器
./update.sh                 # 升级到最近一次构建的镜像
```

---

## CI / 多架构构建

[`.github/workflows/docker.yml`](./.github/workflows/docker.yml) 在每次 push 到 `main` 时，通过 QEMU + Buildx 并行构建 `linux/amd64` + `linux/arm64`，并把单一的多架构 manifest 推送到 GHCR。也支持手动触发（Actions 页面 → "Run workflow"），可附带额外的 tag。

---

## 许可证

按"原样"提供，用于个人开发用途。
