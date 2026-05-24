# swamp-sandbox

A hands-on learning environment for [swamp](https://swamp.club) — an AI-native
automation tool that uses typed models, versioned data, and agentic workflows
to observe and manage infrastructure.

This repo runs swamp + Claude Code inside isolated [Coder](https://coder.com)
workspace containers via Docker Compose. You get a safe, disposable sandbox
to experiment with swamp models, methods, data queries, and workflows without
touching your host machine or any production systems.

## What you'll learn

- **Models and methods** — swamp's core primitive: typed schemas with executable
  methods (validate, transform, enrich) that produce versioned, queryable output
- **Data queries with CEL** — query model output across versions using Common
  Expression Language
- **Workflows** — orchestrate multiple models into DAGs with parallel jobs and
  typed dependencies
- **Extensions** — build custom model types in TypeScript when built-in types
  don't cover your domain

Each concept builds on the last. Start with the examples, then explore freely
inside the sandbox.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) and Docker Compose (or Podman)
- Make, curl, jq
- Claude Code credentials (one of the following):
  - `ANTHROPIC_API_KEY` — direct [Anthropic API](https://console.anthropic.com/) access
  - `CLAUDE_CODE_USE_BEDROCK` + `AWS_BEARER_TOKEN_BEDROCK` — [AWS Bedrock](https://docs.aws.amazon.com/bedrock/) access

The Coder CLI is installed automatically from the running server (no external
install needed).

Works on Linux (x86_64 and ARM), macOS (Apple Silicon and Intel), and WSL2.

## Quickstart

Three commands to go from clone to running sandbox:

```bash
make up                # Start the Coder server
make login             # Create admin user and authenticate CLI (fully automatic)
make setup             # Push template and create workspace
```

`make login` creates a default admin account, installs a repo-local Coder CLI
matching the server version, and authenticates — no browser interaction needed.

`make setup` needs credentials so Claude Code can authenticate inside the
workspace container. It looks for them in two places (in this order):

1. **Shell environment** — checks for exported env vars
2. **`~/.claude/settings.json`** — reads the `env` object if vars aren't in the shell

The credentials it looks for (one set required):

| Provider | Variables |
|----------|-----------|
| Anthropic API | `ANTHROPIC_API_KEY` |
| AWS Bedrock | `CLAUDE_CODE_USE_BEDROCK` + `AWS_BEARER_TOKEN_BEDROCK` |

These values are passed as Coder workspace parameters and injected as
environment variables inside the container. They are **not** logged, committed,
or sent anywhere other than the locally-running Coder server. The container
is ephemeral — credentials exist only for the lifetime of the workspace.

Export your credentials before running, or ensure they're in your settings file:

```bash
# Option A: Anthropic API
export ANTHROPIC_API_KEY=sk-ant-...

# Option B: AWS Bedrock
export CLAUDE_CODE_USE_BEDROCK=1
export AWS_BEARER_TOKEN_BEDROCK=...
```

Once the workspace is running, dispatch work via Coder tasks:

```bash
make task-inspect                          # Run the sandbox inspection example
make task PROMPT="your instructions here"  # Run a custom task
make tasks                                 # List running tasks
```

You can also SSH into the workspace directly:

```bash
make ssh
```

To tear down:

```bash
make clean             # Delete the workspace
make down              # Stop the Coder server
make reset             # Stop and remove all data (full reset)
```

Run `make help` to see all available targets.

## Podman users

The Makefile auto-detects your Docker or Podman socket. Podman requires the
socket to be accessible to the Coder process inside the container:

```bash
chmod 666 /run/user/1000/podman/podman.sock
```

Run this before `make up`. Everything else is identical.

## How tasks work

Coder tasks dispatch Claude Code inside the sandbox workspace. Each task
runs in isolation — Claude receives your prompt, executes inside the container,
and you can follow the output with `coder tasks logs`.

The `task-inspect` target runs the `sandbox-inspect` swamp model, which reports
the container's hostname, OS, tools, and network interfaces — demonstrating
that execution is sandboxed from your host.

## Examples

Each example lives in its own directory under `examples/` with a dedicated
README explaining what it demonstrates and how to run it.

| Example | Description |
|---------|-------------|
| [01-sandbox-inspect](examples/01-sandbox-inspect/) | Inspect the sandbox environment to verify isolation |
| [02-typed-observation](examples/02-typed-observation/) | Observe system state as versioned, typed data |
| [03-cel-queries](examples/03-cel-queries/) | Query model output with CEL expressions |
| [04-workflow-dag](examples/04-workflow-dag/) | Parallel workflow replacing sequential pipelines |
| [05-extension-model](examples/05-extension-model/) | Custom TypeScript model with Zod schema validation |
| [06-architect-loop](examples/06-architect-loop/) | Full agentic lifecycle: observe → reason → act → verify |

## Exploring interactively

After `make ssh`, you're inside a fully equipped sandbox. Try these to get
oriented:

```bash
swamp --help                              # See all commands
swamp model search                        # List models in this workspace
swamp model type search                   # Browse available model types
swamp model method run sandbox-inspect execute  # Run the example model
swamp model output get sandbox-inspect    # View the output data
```

Claude Code is also available inside the workspace. Start it with `claude` and
ask it to help you create models, run workflows, or explore swamp's capabilities.
The swamp skills are pre-installed, so Claude knows how to work with swamp out
of the box.

## Step-by-step guide

If you prefer to run commands directly without Make, this section walks through
each step.

### 1. Start the Coder server

**Docker:**

```bash
docker compose up -d
```

**Podman:**

```bash
chmod 666 /run/user/1000/podman/podman.sock
CONTAINER_SOCKET=/run/user/1000/podman/podman.sock docker compose up -d
```

Wait a few seconds, then verify it's running:

```bash
curl -s -o /dev/null -w "%{http_code}" http://localhost:3000
# Should print: 200
```

### 2. Create the first user and log in

Create the admin account via the API:

```bash
curl -s -X POST http://localhost:3000/api/v2/users/first \
  -H 'Content-Type: application/json' \
  -d '{"email":"admin@swamp-sandbox.local","username":"admin","password":"SandboxDemo1","trial":false}'
```

Get a session token and authenticate the CLI:

```bash
TOKEN=$(curl -s -X POST http://localhost:3000/api/v2/users/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"admin@swamp-sandbox.local","password":"SandboxDemo1"}' | jq -r '.session_token')

coder login http://localhost:3000 --token "$TOKEN"
```

### 3. Push the template and create a workspace

```bash
coder templates push sandbox --directory ./coder/template --yes
```

This builds the workspace image (Debian slim with swamp and Claude Code
pre-installed) and registers the template. The first push takes a couple of
minutes while Terraform downloads providers and Docker builds the image.

```bash
# For Anthropic API:
coder create my-sandbox --template sandbox \
  --parameter claude_provider=anthropic \
  --parameter anthropic_api_key=YOUR_API_KEY_HERE \
  --yes

# For AWS Bedrock:
coder create my-sandbox --template sandbox \
  --parameter claude_provider=bedrock \
  --parameter aws_bearer_token_bedrock=YOUR_TOKEN \
  --parameter claude_code_use_bedrock=1 \
  --yes
```

### 4. Dispatch work with Coder tasks

```bash
coder tasks create --template sandbox \
  "Initialize swamp and run swamp model method run sandbox-inspect execute"
```

Or SSH into the workspace directly:

```bash
coder ssh my-sandbox
```

### Cleanup

```bash
coder delete my-sandbox --yes   # Delete the workspace
docker compose down              # Stop the Coder server
docker compose down -v           # Full reset (removes all data)
```

## How it works

Docker Compose runs a Coder server that uses your host Docker daemon to
provision workspace containers. Each workspace is built from a Debian slim-based
image with Claude Code and swamp pre-installed. The image is multi-arch
(x86_64 and ARM).

Users provide their Anthropic API key as a workspace parameter. Coder tasks
dispatch Claude Code inside the container, which runs swamp models in isolation
from the host.

No Kubernetes or cloud accounts required.

## Adding examples

Create a new directory under `examples/` following the naming convention
`NN-description/`. Add a README explaining the example and any model or
workflow definitions needed. See the existing examples for the pattern.
