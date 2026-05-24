CODER_URL ?= http://localhost:3000
TEMPLATE_DIR ?= ./coder/template
TEMPLATE_NAME ?= sandbox
WORKSPACE_NAME ?= my-sandbox
CODER_EMAIL ?= admin@swamp-sandbox.local
CODER_PASSWORD ?= SandboxDemo1

# Repo-local Coder CLI (installed from the running server to avoid version mismatch)
CODER_PREFIX := $(CURDIR)/.local
CODER := $(CODER_PREFIX)/bin/coder

# Auto-detect container socket: prefer Docker, fall back to Podman rootless
CONTAINER_SOCKET ?= $(shell \
	if [ -S /var/run/docker.sock ]; then echo /var/run/docker.sock; \
	elif [ -S /run/user/$$(id -u)/podman/podman.sock ]; then echo /run/user/$$(id -u)/podman/podman.sock; \
	else echo /var/run/docker.sock; fi)

.PHONY: help bootstrap destroy up down reset login setup ssh task task-inspect tasks clean status coder-cli models

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

$(CODER):
	@echo "Installing Coder CLI from server at $(CODER_URL)..."
	@curl -fsSL $(CODER_URL)/install.sh | sh -s -- --prefix $(CODER_PREFIX)

coder-cli: $(CODER) ## Install repo-local Coder CLI matching the server version

# --- Swamp model instances (idempotent, created once) ---

models: ## Ensure swamp model instances exist for infrastructure management
	@swamp model search --json 2>/dev/null | jq -e '.results[] | select(.name == "coder-server")' > /dev/null 2>&1 \
		|| (echo "Creating coder-server model..." && swamp model create sandbox/coder-server coder-server --json > /dev/null)
	@swamp model search --json 2>/dev/null | jq -e '.results[] | select(.name == "coder-template")' > /dev/null 2>&1 \
		|| (echo "Creating coder-template model..." && swamp model create sandbox/coder-template coder-template --json > /dev/null)
	@swamp model search --json 2>/dev/null | jq -e '.results[] | select(.name == "coder-workspace")' > /dev/null 2>&1 \
		|| (echo "Creating coder-workspace model..." && swamp model create sandbox/coder-workspace coder-workspace --json > /dev/null)
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
	CONTAINER_SOCKET=$(CONTAINER_SOCKET) docker compose up -d
	@echo "Waiting for Coder server..."
	@for i in 1 2 3 4 5 6 7 8 9 10; do \
		if curl -s -o /dev/null -w '' $(CODER_URL) 2>/dev/null; then \
			echo "Coder is ready at $(CODER_URL)"; \
			exit 0; \
		fi; \
		sleep 2; \
	done; \
	echo "Coder did not start in time. Check: docker compose logs"

down: ## Stop the Coder server
	docker compose down

reset: ## Stop and remove all data (full reset)
	@docker ps -aq --filter "label=coder.owner" | xargs -r docker rm -f 2>/dev/null || true
	docker compose down -v
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
			echo "Then re-run: make setup"; \
			exit 1; \
		fi; \
	fi; \
	PROVIDER="anthropic"; \
	if [ -n "$$BEDROCK_MODE" ] && [ -n "$$BEDROCK_TOKEN" ]; then \
		PROVIDER="bedrock"; \
	fi; \
	echo "=== Pushing template (provider: $$PROVIDER) ==="; \
	swamp model method run coder-template push \
		--input "variables.preset_claude_provider=$$PROVIDER" \
		--input "variables.preset_anthropic_api_key=$${API_KEY:-}" \
		--input "variables.preset_aws_bearer_token_bedrock=$${BEDROCK_TOKEN:-}" \
		--input "variables.preset_claude_code_use_bedrock=$${BEDROCK_MODE:-}" \
		--input "variables.preset_aws_region=$${AWS_REGION:-us-east-1}"; \
	echo ""; \
	echo "=== Creating workspace (provider: $$PROVIDER) ==="; \
	swamp model method run coder-workspace create \
		--input "provider=$$PROVIDER" \
		--input "anthropicApiKey=$${API_KEY:-}" \
		--input "awsBearerTokenBedrock=$${BEDROCK_TOKEN:-}" \
		--input "claudeCodeUseBedrock=$${BEDROCK_MODE:-}" \
		--input "awsRegion=$${AWS_REGION:-us-east-1}"; \
	echo ""; \
	echo "Workspace ready. Run tasks with:"; \
	echo "  make task-inspect    # Run the sandbox inspection example"; \
	echo "  make task PROMPT=\"your prompt here\"  # Run a custom task"

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
