CODER_URL ?= http://localhost:3000
TEMPLATE_DIR ?= ./coder/template
TEMPLATE_NAME ?= sandbox
WORKSPACE_NAME ?= my-sandbox
CODER_EMAIL ?= admin@swamp-sandbox.local
CODER_PASSWORD ?= SandboxDemo1

# Repo-local Coder CLI (installed from the running server to avoid version mismatch)
CODER_PREFIX := $(CURDIR)/.local
CODER := $(CODER_PREFIX)/bin/coder

# Auto-detect container runtime and socket path
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
  # macOS: check for podman machine first, then Docker Desktop
  PODMAN_MACHINE_STATE := $(shell podman machine inspect --format '{{.State}}' 2>/dev/null)
  ifeq ($(PODMAN_MACHINE_STATE),running)
    CONTAINER_SOCKET ?= $(shell podman machine inspect --format '{{.ConnectionInfo.PodmanSocket.Path}}' 2>/dev/null)
    COMPOSE_FILE ?= docker-compose.podman-machine.yaml
  else
    CONTAINER_SOCKET ?= /var/run/docker.sock
    COMPOSE_FILE ?= docker-compose.yaml
  endif
else
  # Linux: prefer Docker, fall back to rootless Podman, then rootful Podman
  CONTAINER_SOCKET ?= $(shell \
    if [ -S /var/run/docker.sock ]; then echo /var/run/docker.sock; \
    elif [ -S /run/user/$$(id -u)/podman/podman.sock ]; then echo /run/user/$$(id -u)/podman/podman.sock; \
    elif [ -S /run/podman/podman.sock ]; then echo /run/podman/podman.sock; \
    else echo /var/run/docker.sock; fi)
  COMPOSE_FILE ?= docker-compose.yaml
endif

.PHONY: help bootstrap destroy up down reset login setup ssh task task-inspect tasks clean status coder-cli vault models

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

$(CODER):
	@echo "Installing Coder CLI from server at $(CODER_URL)..."
	@curl -fsSL $(CODER_URL)/install.sh | sh -s -- --prefix $(CODER_PREFIX)

coder-cli: $(CODER) ## Install repo-local Coder CLI matching the server version

# --- Vault and model instances (idempotent, created once) ---

vault: ## Ensure the sandbox-creds vault exists and has credentials stored
	@swamp vault search --json 2>/dev/null | jq -e '.results[] | select(.name == "sandbox-creds")' > /dev/null 2>&1 \
		|| (echo "Creating sandbox-creds vault..." && swamp vault create local_encryption sandbox-creds --json > /dev/null)
	@BEDROCK_TOKEN="$${AWS_BEARER_TOKEN_BEDROCK:-}"; \
	BEDROCK_MODE="$${CLAUDE_CODE_USE_BEDROCK:-}"; \
	API_KEY="$${ANTHROPIC_API_KEY:-}"; \
	AWS_REGION="$${AWS_REGION:-}"; \
	if [ -z "$$BEDROCK_TOKEN" ] || [ -z "$$BEDROCK_MODE" ] || [ -z "$$API_KEY" ]; then \
		SETTINGS="$${HOME}/.claude/settings.json"; \
		if [ -f "$$SETTINGS" ]; then \
			[ -z "$$BEDROCK_TOKEN" ] && BEDROCK_TOKEN=$$(jq -r '.env.AWS_BEARER_TOKEN_BEDROCK // empty' "$$SETTINGS"); \
			[ -z "$$BEDROCK_MODE" ] && BEDROCK_MODE=$$(jq -r '.env.CLAUDE_CODE_USE_BEDROCK // empty' "$$SETTINGS"); \
			[ -z "$$API_KEY" ] && API_KEY=$$(jq -r '.env.ANTHROPIC_API_KEY // empty' "$$SETTINGS"); \
			[ -z "$$AWS_REGION" ] && AWS_REGION=$$(jq -r '.env.AWS_REGION // empty' "$$SETTINGS"); \
		fi; \
	fi; \
	if [ -z "$$BEDROCK_MODE" ] || [ -z "$$BEDROCK_TOKEN" ]; then \
		if [ -z "$$API_KEY" ]; then \
			echo "No Claude Code credentials detected."; \
			echo ""; \
			echo "Set one of (in environment or ~/.claude/settings.json):"; \
			echo "  ANTHROPIC_API_KEY              — for direct Anthropic API access"; \
			echo "  CLAUDE_CODE_USE_BEDROCK +"; \
			echo "  AWS_BEARER_TOKEN_BEDROCK       — for AWS Bedrock access"; \
			echo ""; \
			echo "Then re-run: make vault"; \
			exit 1; \
		fi; \
	fi; \
	PROVIDER="anthropic"; \
	if [ -n "$$BEDROCK_MODE" ] && [ -n "$$BEDROCK_TOKEN" ]; then \
		PROVIDER="bedrock"; \
	fi; \
	echo "$$PROVIDER" | swamp vault put sandbox-creds CLAUDE_PROVIDER > /dev/null 2>&1; \
	echo "$${API_KEY:-}" | swamp vault put sandbox-creds ANTHROPIC_API_KEY > /dev/null 2>&1; \
	echo "$${BEDROCK_TOKEN:-}" | swamp vault put sandbox-creds AWS_BEARER_TOKEN_BEDROCK > /dev/null 2>&1; \
	echo "$${BEDROCK_MODE:-}" | swamp vault put sandbox-creds CLAUDE_CODE_USE_BEDROCK > /dev/null 2>&1; \
	echo "$${AWS_REGION:-us-east-1}" | swamp vault put sandbox-creds AWS_REGION > /dev/null 2>&1; \
	echo "Credentials stored in vault (provider: $$PROVIDER)."

models: vault ## Ensure swamp model instances exist for infrastructure management
	@swamp model search --json 2>/dev/null | jq -e '.results[] | select(.name == "coder-server")' > /dev/null 2>&1 \
		|| (echo "Creating coder-server model..." && swamp model create sandbox/coder-server coder-server --json > /dev/null)
	@swamp model search --json 2>/dev/null | jq -e '.results[] | select(.name == "coder-template")' > /dev/null 2>&1 \
		|| (echo "Creating coder-template model..." \
		&& swamp model create sandbox/coder-template coder-template \
			--global-arg 'claudeProvider=$${{ vault.get(sandbox-creds, CLAUDE_PROVIDER) }}' \
			--global-arg 'anthropicApiKey=$${{ vault.get(sandbox-creds, ANTHROPIC_API_KEY) }}' \
			--global-arg 'awsBearerTokenBedrock=$${{ vault.get(sandbox-creds, AWS_BEARER_TOKEN_BEDROCK) }}' \
			--global-arg 'claudeCodeUseBedrock=$${{ vault.get(sandbox-creds, CLAUDE_CODE_USE_BEDROCK) }}' \
			--global-arg 'awsRegion=$${{ vault.get(sandbox-creds, AWS_REGION) }}' \
			--json > /dev/null)
	@swamp model search --json 2>/dev/null | jq -e '.results[] | select(.name == "coder-workspace")' > /dev/null 2>&1 \
		|| (echo "Creating coder-workspace model..." \
		&& swamp model create sandbox/coder-workspace coder-workspace \
			--global-arg 'claudeProvider=$${{ vault.get(sandbox-creds, CLAUDE_PROVIDER) }}' \
			--global-arg 'anthropicApiKey=$${{ vault.get(sandbox-creds, ANTHROPIC_API_KEY) }}' \
			--global-arg 'awsBearerTokenBedrock=$${{ vault.get(sandbox-creds, AWS_BEARER_TOKEN_BEDROCK) }}' \
			--global-arg 'claudeCodeUseBedrock=$${{ vault.get(sandbox-creds, CLAUDE_CODE_USE_BEDROCK) }}' \
			--global-arg 'awsRegion=$${{ vault.get(sandbox-creds, AWS_REGION) }}' \
			--json > /dev/null)
	@swamp model search --json 2>/dev/null | jq -e '.results[] | select(.name == "coder-task")' > /dev/null 2>&1 \
		|| (echo "Creating coder-task model..." && swamp model create sandbox/coder-task coder-task --json > /dev/null)

# --- Composite targets ---

bootstrap: up login setup ## From zero to working sandbox (up + login + setup)

destroy: clean down reset ## Full teardown: delete workspace, stop server, remove data

# --- Server lifecycle ---
# Docker Compose is the one layer below swamp — swamp observes it but doesn't
# start it, because swamp itself doesn't depend on the Coder server running.

up: ## Start the Coder server
	@if [ ! -S "$(CONTAINER_SOCKET)" ]; then \
		echo "Error: Container socket not found at $(CONTAINER_SOCKET)"; \
		echo "Set CONTAINER_SOCKET to your Docker or Podman socket path."; \
		exit 1; \
	fi
	CONTAINER_SOCKET=$(CONTAINER_SOCKET) docker compose -f $(COMPOSE_FILE) up -d
	@echo "Waiting for Coder server to be ready..."
	@timeout 120 sh -c 'until curl -fsS http://localhost:3000/api/v2/buildinfo >/dev/null 2>&1; do sleep 2; done' \
		|| { echo "=== Container status ==="; docker compose ps; echo "=== Container logs ==="; docker compose logs --tail 50; exit 1; }
	@echo "Coder is ready at $(CODER_URL)"

down: ## Stop the Coder server
	docker compose -f $(COMPOSE_FILE) down

reset: ## Stop and remove all data (full reset)
	@docker ps -aq --filter "label=coder.owner" | xargs -r docker rm -f 2>/dev/null || true
	docker compose -f $(COMPOSE_FILE) down -v
	@docker rmi swamp-sandbox:latest 2>/dev/null || true

# --- Auth ---

login: $(CODER) ## Authenticate the Coder CLI (creates first user on initial run)
	@STATUS=$$(curl -s -o /dev/null -w '%{http_code}' $(CODER_URL)/api/v2/users/first); \
	if [ "$$STATUS" = "404" ]; then \
		echo "Creating first user..."; \
		curl -s -X POST $(CODER_URL)/api/v2/users/first \
			-H 'Content-Type: application/json' \
			-d '{"email":"$(CODER_EMAIL)","username":"admin","password":"$(CODER_PASSWORD)","trial":false}' > /dev/null; \
		echo "First user created."; \
	else \
		echo "First user already exists."; \
	fi
	@echo ""
	@echo "Web UI: $(CODER_URL)"
	@echo "  Email:    $(CODER_EMAIL)"
	@echo "  Password: $(CODER_PASSWORD)"
	@echo ""
	@echo "Authenticating CLI..."
	@TOKEN=$$(curl -s -X POST $(CODER_URL)/api/v2/users/login \
		-H 'Content-Type: application/json' \
		-d '{"email":"$(CODER_EMAIL)","password":"$(CODER_PASSWORD)"}' | jq -r '.session_token'); \
	if [ "$$TOKEN" = "null" ] || [ -z "$$TOKEN" ]; then \
		echo "Failed to get session token. Log in manually:"; \
		echo "  Email:    $(CODER_EMAIL)"; \
		echo "  Password: $(CODER_PASSWORD)"; \
		$(CODER) login $(CODER_URL); \
	else \
		$(CODER) login $(CODER_URL) --token "$$TOKEN"; \
	fi

# --- Template + workspace (via swamp models) ---

setup: models $(CODER) ## Push template and create workspace (run after login)
	@echo "=== Pushing template (credentials from vault) ==="
	@swamp model method run coder-template push
	@echo ""
	@WS_STATUS=$$($(CODER) list --output json 2>/dev/null | jq -r '.[] | select(.name == "$(WORKSPACE_NAME)") | .latest_build.status'); \
	if [ "$$WS_STATUS" = "running" ] || [ "$$WS_STATUS" = "starting" ]; then \
		echo "=== Workspace '$(WORKSPACE_NAME)' already running, updating template ==="; \
		$(CODER) update $(WORKSPACE_NAME) --template $(TEMPLATE_NAME) --yes 2>/dev/null || true; \
	elif [ -n "$$WS_STATUS" ]; then \
		echo "=== Workspace '$(WORKSPACE_NAME)' exists but is $$WS_STATUS, rebuilding ==="; \
		$(CODER) delete $(WORKSPACE_NAME) --orphan --yes 2>/dev/null || true; \
		swamp model method run coder-workspace create; \
	else \
		echo "=== Creating workspace (credentials from vault) ==="; \
		swamp model method run coder-workspace create; \
	fi
	@echo ""
	@echo "Workspace ready. Run tasks with:"
	@echo "  make task-inspect    # Run the sandbox inspection example"
	@echo "  make task PROMPT=\"your prompt here\"  # Run a custom task"

# --- Task dispatch (via swamp model) ---

task: models ## Run a Coder task with a prompt (usage: make task PROMPT="...")
	@if [ -z "$(PROMPT)" ]; then \
		echo "Usage: make task PROMPT=\"your prompt here\""; \
		echo ""; \
		echo "Example:"; \
		echo "  make task PROMPT=\"Run swamp model method run sandbox-inspect execute\""; \
		exit 1; \
	fi
	@swamp model method run coder-task dispatch --input "prompt=$(PROMPT)"

task-inspect: models ## Run the sandbox-inspect example as a Coder task
	@swamp model method run coder-task dispatch \
		--input "prompt=Initialize swamp with 'swamp init', then run 'swamp model method run sandbox-inspect execute' and show me the output"

tasks: models ## List running tasks
	@swamp model method run coder-task list

# --- Observation ---

status: models ## Observe all sandbox infrastructure via swamp models
	@echo "=== Server ==="
	@swamp model method run coder-server status
	@echo ""
	@echo "=== Template ==="
	@swamp model method run coder-template describe
	@echo ""
	@echo "=== Workspace ==="
	@swamp model method run coder-workspace status
	@echo ""
	@echo "=== Tasks ==="
	@swamp model method run coder-task list

# --- Workspace access ---

ssh: $(CODER) ## SSH into the sandbox workspace
	$(CODER) ssh $(WORKSPACE_NAME)

# --- Cleanup ---

clean: ## Delete the sandbox workspace
	@swamp model method run coder-workspace delete 2>/dev/null \
		|| ([ -x "$(CODER)" ] && $(CODER) delete $(WORKSPACE_NAME) --orphan --yes) \
		|| true
