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

.PHONY: help bootstrap destroy up down reset login setup workspace ssh task task-inspect tasks clean status coder-cli

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

$(CODER):
	@echo "Installing Coder CLI from server at $(CODER_URL)..."
	@curl -fsSL $(CODER_URL)/install.sh | sh -s -- --prefix $(CODER_PREFIX)

coder-cli: $(CODER) ## Install repo-local Coder CLI matching the server version

bootstrap: up login setup ## From zero to working sandbox (up + login + setup)

destroy: clean down reset ## Full teardown: delete workspace, stop server, remove data

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

setup: $(CODER) ## Push template and create workspace (run after login)
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
	echo "=== Pushing workspace template (provider: $$PROVIDER) ==="; \
	$(CODER) templates push $(TEMPLATE_NAME) --directory $(TEMPLATE_DIR) \
		--variable "preset_claude_provider=$$PROVIDER" \
		--variable "preset_anthropic_api_key=$${API_KEY:-}" \
		--variable "preset_aws_bearer_token_bedrock=$${BEDROCK_TOKEN:-}" \
		--variable "preset_claude_code_use_bedrock=$${BEDROCK_MODE:-}" \
		--variable "preset_aws_region=$${AWS_REGION:-us-east-1}" --yes; \
	echo ""; \
	echo "=== Creating workspace ==="; \
	echo "Detected $$PROVIDER auth"; \
	$(CODER) create $(WORKSPACE_NAME) --template $(TEMPLATE_NAME) \
		--parameter "AI Prompt=" \
		--parameter "claude_provider=$$PROVIDER" \
		--parameter "anthropic_api_key=$${API_KEY:-}" \
		--parameter "aws_bearer_token_bedrock=$${BEDROCK_TOKEN:-}" \
		--parameter "claude_code_use_bedrock=$${BEDROCK_MODE:-}" \
		--parameter "aws_region=$${AWS_REGION:-us-east-1}" --yes; \
	echo ""; \
	echo "Workspace ready. Run tasks with:"; \
	echo "  make task-inspect    # Run the sandbox inspection example"; \
	echo "  make task PROMPT=\"your prompt here\"  # Run a custom task"

ssh: $(CODER) ## SSH into the sandbox workspace
	$(CODER) ssh $(WORKSPACE_NAME)

task: $(CODER) ## Run a Coder task with a prompt (usage: make task PROMPT="...")
	@if [ -z "$(PROMPT)" ]; then \
		echo "Usage: make task PROMPT=\"your prompt here\""; \
		echo ""; \
		echo "Example:"; \
		echo "  make task PROMPT=\"Run swamp model method run sandbox-inspect execute\""; \
		exit 1; \
	fi
	$(CODER) tasks create --template $(TEMPLATE_NAME) --preset swamp-sandbox "$(PROMPT)"

task-inspect: $(CODER) ## Run the sandbox-inspect example as a Coder task
	$(CODER) tasks create --template $(TEMPLATE_NAME) --preset swamp-sandbox \
		"Initialize swamp with 'swamp init', then run 'swamp model method run sandbox-inspect execute' and show me the output"

tasks: $(CODER) ## List running tasks
	$(CODER) tasks list

clean: $(CODER) ## Delete the sandbox workspace
	-$(CODER) delete $(WORKSPACE_NAME) --orphan --yes

status: ## Show Coder server and workspace status
	@echo "=== Server ==="
	@curl -s -o /dev/null -w "Coder server: HTTP %{http_code}\n" $(CODER_URL) 2>/dev/null || echo "Coder server: not running"
	@echo ""
	@echo "=== Workspaces ==="
	@$(CODER) list 2>/dev/null || echo "Not logged in. Run: make login"
