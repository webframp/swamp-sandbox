CODER_URL ?= http://localhost:3000
TEMPLATE_DIR ?= ./coder/template
TEMPLATE_NAME ?= sandbox
WORKSPACE_NAME ?= my-sandbox
CODER_EMAIL ?= admin@swamp-sandbox.local
CODER_PASSWORD ?= SandboxDemo1

# Auto-detect container socket: prefer Docker, fall back to Podman rootless
CONTAINER_SOCKET ?= $(shell \
	if [ -S /var/run/docker.sock ]; then echo /var/run/docker.sock; \
	elif [ -S /run/user/$$(id -u)/podman/podman.sock ]; then echo /run/user/$$(id -u)/podman/podman.sock; \
	else echo /var/run/docker.sock; fi)

.PHONY: help up down reset login setup workspace ssh task task-inspect tasks clean status

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

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
	docker compose down -v

login: ## Authenticate the Coder CLI (creates first user on initial run)
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
	@echo "Authenticating CLI..."
	@TOKEN=$$(curl -s -X POST $(CODER_URL)/api/v2/users/login \
		-H 'Content-Type: application/json' \
		-d '{"email":"$(CODER_EMAIL)","password":"$(CODER_PASSWORD)"}' | jq -r '.session_token'); \
	if [ "$$TOKEN" = "null" ] || [ -z "$$TOKEN" ]; then \
		echo "Failed to get session token. Log in manually:"; \
		echo "  Email:    $(CODER_EMAIL)"; \
		echo "  Password: $(CODER_PASSWORD)"; \
		coder login $(CODER_URL); \
	else \
		coder login $(CODER_URL) --token "$$TOKEN"; \
	fi

setup: ## Push template and create workspace (run after login)
	@echo "=== Pushing workspace template ==="
	coder templates push $(TEMPLATE_NAME) --directory $(TEMPLATE_DIR) --yes
	@echo ""
	@echo "=== Creating workspace ==="
	@if [ -z "$(ANTHROPIC_API_KEY)" ]; then \
		printf "Enter your Anthropic API key: "; \
		read -r key; \
		coder create $(WORKSPACE_NAME) --template $(TEMPLATE_NAME) \
			--parameter "anthropic_api_key=$$key" --yes; \
	else \
		coder create $(WORKSPACE_NAME) --template $(TEMPLATE_NAME) \
			--parameter "anthropic_api_key=$(ANTHROPIC_API_KEY)" --yes; \
	fi
	@echo ""
	@echo "Workspace ready. Run tasks with:"
	@echo "  make task-inspect    # Run the sandbox inspection example"
	@echo "  make task PROMPT=\"your prompt here\"  # Run a custom task"

ssh: ## SSH into the sandbox workspace
	coder ssh $(WORKSPACE_NAME)

task: ## Run a Coder task with a prompt (usage: make task PROMPT="...")
	@if [ -z "$(PROMPT)" ]; then \
		echo "Usage: make task PROMPT=\"your prompt here\""; \
		echo ""; \
		echo "Example:"; \
		echo "  make task PROMPT=\"Run swamp model method run sandbox-inspect execute\""; \
		exit 1; \
	fi
	coder tasks create --template $(TEMPLATE_NAME) "$(PROMPT)"

task-inspect: ## Run the sandbox-inspect example as a Coder task
	coder tasks create --template $(TEMPLATE_NAME) \
		"Initialize swamp with 'swamp init', then run 'swamp model method run sandbox-inspect execute' and show me the output"

tasks: ## List running tasks
	coder tasks list

clean: ## Delete the sandbox workspace
	coder delete $(WORKSPACE_NAME) --yes

status: ## Show Coder server and workspace status
	@echo "=== Server ==="
	@curl -s -o /dev/null -w "Coder server: HTTP %{http_code}\n" $(CODER_URL) 2>/dev/null || echo "Coder server: not running"
	@echo ""
	@echo "=== Workspaces ==="
	@coder list 2>/dev/null || echo "Not logged in. Run: make login"
