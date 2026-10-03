.PHONY: build run clean ssh

# 加载 .arg 文件 (如果存在)
-include .arg

IMAGE_NAME ?= rust-dev
CONTAINER_NAME ?= rust-dev-container
SSH_PORT ?= 2222
SECRETS_DIR ?= ./secrets

# 构建参数 (仅当变量已定义时传递)
BUILD_ARGS =
ifdef RUST_TAG
	BUILD_ARGS += --build-arg RUST_TAG=$(RUST_TAG)
endif
ifdef APT_MIRROR
	BUILD_ARGS += --build-arg APT_MIRROR=$(APT_MIRROR)
endif
ifdef CLAUDE_CODE
	BUILD_ARGS += --build-arg CLAUDE_CODE=$(CLAUDE_CODE)
endif
ifdef OPENCODE
	BUILD_ARGS += --build-arg OPENCODE=$(OPENCODE)
endif
ifdef CODEX
	BUILD_ARGS += --build-arg CODEX=$(CODEX)
endif
ifdef NODE
	BUILD_ARGS += --build-arg NODE=$(NODE)
endif
ifdef ZSH
	BUILD_ARGS += --build-arg ZSH=$(ZSH)
endif
ifdef PYTHON
	BUILD_ARGS += --build-arg PYTHON=$(PYTHON)
endif
ifdef WASM
	BUILD_ARGS += --build-arg WASM=$(WASM)
endif
ifdef ANDROID
	BUILD_ARGS += --build-arg ANDROID=$(ANDROID)
endif
ifdef SSH
	BUILD_ARGS += --build-arg SSH=$(SSH)
endif
ifdef BUILD_PROXY
	BUILD_ARGS += --build-arg BUILD_PROXY=$(BUILD_PROXY)
endif
ifdef GIT_USER
	BUILD_ARGS += --build-arg GIT_USER=$(GIT_USER)
endif
ifdef GIT_EMAIL
	BUILD_ARGS += --build-arg GIT_EMAIL=$(GIT_EMAIL)
endif

build:
	docker build $(BUILD_ARGS) -t $(IMAGE_NAME) .

run:
	docker run -d \
	-p $(SSH_PORT):22 \
	--name $(CONTAINER_NAME) \
	--hostname $(CONTAINER_NAME) \
	--init \
	-v $(SECRETS_DIR):/run/secrets:ro \
	-v $(CONTAINER_NAME)-data:/root/workspace \
	$(IMAGE_NAME)

ssh:
	ssh root@localhost -p $(SSH_PORT)

stop:
	docker stop $(CONTAINER_NAME)

rm:
	docker rm -f $(CONTAINER_NAME)

clean:
	docker rmi $(IMAGE_NAME)

shell:
	docker exec -it $(CONTAINER_NAME) sh -c 'command -v zsh >/dev/null 2>&1 && exec zsh -l || exec bash -l'

# 创建 secrets 目录和示例文件
init-secrets:
	mkdir -p $(SECRETS_DIR)
	@if [ ! -f $(SECRETS_DIR)/ssh_password ]; then \
		echo "docker" > $(SECRETS_DIR)/ssh_password; \
		echo "Created $(SECRETS_DIR)/ssh_password with default password 'docker'"; \
	fi
	@if [ ! -f $(SECRETS_DIR)/zp_key ]; then \
		echo "your_zhipu_api_key_here" > $(SECRETS_DIR)/zp_key; \
		echo "Created $(SECRETS_DIR)/zp_key - please edit with your actual key"; \
	fi
