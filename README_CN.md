# rust-dev-docker

[![Build and Push Docker Image](https://github.com/wzh19960613/rust-dev-docker/actions/workflows/docker.yml/badge.svg)](https://github.com/wzh19960613/rust-dev-docker/actions/workflows/docker.yml)

用于 Rust 开发的多架构（amd64 + arm64）Docker 镜像，可选集成 AI 编程助手、Node.js、Zsh、Python、WASM 与 Android 目标等工具链。

English documentation: [README.md](./README.md)

---

## 预构建镜像

通过 GitHub Actions 自动构建多架构镜像，发布到 GitHub Container Registry。每次构建都会附带所含 Rust 版本的 tag，并有每日定时任务在新 stable 发布后自动重建。

| Tag | 内容 |
|---|---|
| `latest` / `rust-<版本>` | Rust + SSH + Node.js + Zsh + Python |
| `slim` / `slim-rust-<版本>` | 仅 Rust + SSH |
| `wasm` / `wasm-rust-<版本>` | `latest` + wasm32/WASI 目标 + wasm-pack |
| `android` / `android-rust-<版本>` | `latest` + Android rustup 目标（链接需外部 NDK） |

例如：`ghcr.io/wzh19960613/rust-dev:latest`、`ghcr.io/wzh19960613/rust-dev:rust-1.99.0`、`ghcr.io/wzh19960613/rust-dev:wasm`。

- 架构：`linux/amd64`、`linux/arm64`（Docker 自动选择）
- 每次 push 到 `main` 重新构建；每日定时检查新的 Rust stable 版本并自动构建
- `ci/**` 分支的构建会带 `-ci-<分支名>` tag 后缀，不会覆盖 `latest`

### 拉取与运行

```bash
# 准备 secrets（SSH 密码 + 可选的智谱 API Key）
mkdir -p ./secrets
echo "你的SSH密码" > ./secrets/ssh_password
echo "你的智谱API_Key" > ./secrets/zp_key   # 可选

# 启动容器（--hostname 让 shell 提示符显示容器名）
docker run -d \
  --name rust-dev \
  --hostname rust-dev \
  --init \
  -p 2222:22 \
  -v "$PWD/secrets:/run/secrets:ro" \
  -v rust-dev-data:/root/workspace \
  ghcr.io/wzh19960613/rust-dev:latest

# 通过 SSH 连接
ssh -p 2222 root@localhost
```

`./container.sh`（见下文）会自动传 `--hostname` 和 `--init`。

---

## 镜像内容

基于官方 `rust` 镜像，预装以下工具：

- **Rust 工具链**：`rustc`、`cargo`、`rustfmt`、`clippy`、`rust-analyzer`
- **SSH 服务**：已开启密码登录，通过挂载的 secret 文件配置
- **Node.js**：通过 NodeSource 安装（默认最新 LTS）
- **Zsh**：设为 root 用户的默认登录 shell（SSH 登录直接进 zsh）
- **Python 3**：含 `pip` 和 `venv`
- **WASM / Android 目标**：构建时可选（见下文）
- **AI 编程工具**（构建时可选）：Claude Code、OpenCode、Codex

### Shell 体验

SSH 登录进入的是配置完整的 zsh，而不是裸 shell：

- Tab 补全带选择菜单（`compinit`）、大小写不敏感匹配
- 跨会话持久化历史——当 `/root/workspace` 是卷时，历史文件存于其中，容器升级也不丢
- 彩色提示符 `用户@容器名 路径 (git分支)`——传 `--hostname` 后即显示容器名
- Home/End/Delete/Ctrl+方向键均已绑定，`ls`/`grep` 有颜色
- 全局 `C.UTF-8` locale（中文文件名不会被加引号/转义），SSH 客户端的 `COLORTERM` 会被接受（真彩 CLI 不再降级）

环境变量（cargo 的 `PATH`、`RUSTUP_HOME`、`CARGO_HOME`、`LANG`）通过 `/etc/zsh/zshenv` 与 `/etc/profile.d/` 下发，对非交互 shell 和 `docker exec` 同样生效。

---

## 构建配置

Dockerfile 接受多个构建参数。`NODE`、`ZSH`、`PYTHON` 共用"三态"语义；`WASM`、`ANDROID` 使用命名档位：

| 取值（`NODE`/`ZSH`/`PYTHON`） | 含义 |
|---|---|
| `false` | 不安装 |
| `true` | 安装最新版本 |
| `<版本字符串>` | 安装指定版本 |

| 取值（`WASM`/`ANDROID`） | 含义 |
|---|---|
| `false` | 不包含 |
| `targets` | 仅 rustup 目标（wasm32 + WASI，或 4 个 Android ABI） |
| `tools`（仅 WASM） | `targets` + `wasm-pack` |

### 构建参数一览

| 参数 | 默认值 | 说明 |
|---|---|---|
| `RUST_TAG` | `latest` | 基础 `rust` 镜像的 tag |
| `SSH` | `true` | 安装并启用 SSH 服务 |
| `NODE` | `true` | Node.js：`true` / `false` / `22` / `22.5.0` |
| `ZSH` | `true` | Zsh：`true` / `false` / `5.9`（apt 版本约束） |
| `PYTHON` | `true` | Python：`true` / `false` / `3.11` |
| `WASM` | `false` | WASM：`false` / `targets` / `tools` |
| `ANDROID` | `false` | Android：`false` / `targets`（链接需外部 NDK） |
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

# 加 WASM 工具与 Android 目标
docker build --build-arg WASM=tools --build-arg ANDROID=targets -t rust-dev:cross .

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
make run                   # 运行容器（自动加 --hostname/--init 和数据卷）
make ssh                   # SSH 进入运行中的容器
```

其他 Make 目标：`stop`、`rm`、`clean`、`shell`。

### 使用容器辅助脚本

`container.sh` 是推荐的容器管理方式：给容器打标签、`--ssh` 省略时自动挑选空闲端口、自动设置 `--hostname`/`--init`/`--restart unless-stopped`、数据落在命名卷、并自动维护 SSH 别名：

```bash
./container.sh --dir /path/to/your/project   # 名称与别名: rust-dev-<目录名>
./container.sh --name my-dev                 # 别名: my-dev
./container.sh --image ghcr.io/wzh19960613/rust-dev:wasm --name my-wasm
./container.sh ls                            # 列出容器: 端口、变体、目录
./container.sh sync --name my-dev --dir .    # 把宿主机代码重新推入容器
./container.sh prune                         # 清理已停止容器（--volumes 连数据卷一起删）
```

创建/更新容器后，直接 `ssh <容器名>` 即可连接：脚本会维护 `~/.ssh/rust-dev-containers.conf`，并在 `~/.ssh/config` 中一次性加入托管的 `Include` 块。在 VS Code / Zed 等编辑器的远程配置里直接填别名，不再需要记端口号。

创建选项：`--dir/-d`、`--name/-n`、`--full-name/-f`、`--base-name`、`--ssh/-s`（默认从 2222 起自动找空闲端口）、`--proxy/-p`、`--volume/-v`、`--image/-i`（默认 `rust-dev`；填 GHCR tag 会记录变体供 `update.sh` 使用）。

---

## Secrets（敏感信息）

Secrets 通过挂载到 `/run/secrets`（只读）的文件读取。支持两个文件：

| 文件 | 是否必需 | 用途 |
|---|---|---|
| `ssh_password` | 启用 SSH 时必需 | 设置 root 的 SSH 登录密码 |
| `ssh_authorized_keys` | 否 | 公钥内容，追加到 `/root/.ssh/authorized_keys`，实现免密登录 |
| `zp_key` | 否 | 智谱 AI Key，用于 AI 助手鉴权 |

占位示例见 [`secrets.example/`](./secrets.example)。**切勿提交真实 secrets**——`secrets/` 目录已被 gitignore。

启动时 `entrypoint.sh` 会：

1. 完成智谱鉴权，并在已安装时 reload Claude Code / OpenCode（失败不致命：如离线时容器照常启动）
2. 把 `~/.npm-global`、`~/.npm`、`~/.bun`、`~/.local` 重定向到持久化 workspace 卷——之后安装的 CLI 工具（`npm i -g`、`cargo install`、Claude 安装器等）在容器重建后依然存在；`npm_config_prefix`/`CARGO_INSTALL_ROOT` 已预设，安装会自动落到这些目录
3. 安装 `ssh_authorized_keys`（如存在），把代理环境写入 `/etc/environment` 供 SSH 会话使用
4. 启动 SSH 服务，并以 `exec sleep infinity` 作为 PID 1 常驻

Secrets 不会被输出到容器日志。

---

## 升级已有容器

`update.sh` 会在更新的镜像上重建容器，保留容器名、hostname、端口、卷、环境变量、标签与重启策略。默认从 GHCR 拉取各容器创建时记录的变体（`container.sh --image` 记录），配合 CI 的每日自动构建，一条命令即可把所有容器升到最新 Rust：

```bash
./update.sh                 # 拉取各容器的 GHCR 变体并重建
./update.sh --build         # 重建本地镜像 + 升级本地容器
./update.sh --local         # 用最近一次本地构建升级本地容器
./update.sh --image NAME    # 同 --local，指定镜像名
```

镜像内置 Docker `HEALTHCHECK`（sshd 可达性），异常容器会直接反映在 `docker ps` / `./container.sh ls` 中。

---

## CI / 多架构构建

[`.github/workflows/docker.yml`](./.github/workflows/docker.yml)：

- 每次 push 到 `main` 时，通过 QEMU + Buildx 并行构建全部四个变体（`latest`、`slim`、`wasm`、`android`）的 `linux/amd64` + `linux/arm64` 镜像，并附带 Rust 版本 tag（如 `rust-1.99.0`、`wasm-rust-1.99.0`）推送到 GHCR
- 每日定时任务检查是否有新的 Rust stable：有新版本才构建（版本 tag 已存在则直接跳过）
- `ci/**` 分支的 push 也会构建，但 tag 带 `-ci-<分支名>` 后缀，测试构建绝不会覆盖 `latest`
- `smoke` 任务会真实启动每个变体并通过 SSH 验证：zsh 登录 shell、`C.UTF-8` locale、退格键绑定、补全加载、`ls` 颜色、hostname、cargo 在 `PATH` 上，以及各变体专属内容（wasm 目标、Android 目标等）

也支持手动触发（Actions 页面 → "Run workflow"），可为 full 镜像附带额外的 tag。

---

## 许可证

按"原样"提供，用于个人开发用途。
