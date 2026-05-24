# swamp-sandbox

A hands-on learning environment for [swamp](https://swamp.club) — an AI-native
automation tool that uses typed models, versioned data, and agentic workflows
to observe and manage infrastructure.

This repo runs swamp + Claude Code inside isolated [Coder](https://coder.com)
workspace containers via Docker Compose. You get a safe, disposable sandbox
to experiment with swamp models, methods, data queries, and workflows without
touching your host machine or any production systems.

**Inception:** The sandbox infrastructure itself is managed by swamp. The same
typed models, vault-secured credentials, and CEL-queryable state you learn inside
the workspace are what provision and observe it from the outside. You learn swamp
by using swamp.

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

- [swamp](https://swamp.club) — installed and available on PATH
- [Docker](https://docs.docker.com/get-docker/) and Docker Compose (or Podman)
- Make, curl, jq
- Claude Code credentials (one of the following):
  - `ANTHROPIC_API_KEY` — direct [Anthropic API](https://console.anthropic.com/) access
  - `CLAUDE_CODE_USE_BEDROCK` + `AWS_BEARER_TOKEN_BEDROCK` — [AWS Bedrock](https://docs.aws.amazon.com/bedrock/) access

The Coder CLI is installed automatically from the running server (no external
install needed).

Works on Linux (x86_64 and ARM), macOS (Apple Silicon and Intel), and WSL2.

## Quickstart

One command to go from clone to running sandbox:

```bash
make bootstrap         # Start server, authenticate, store credentials, push template, create workspace
```

This runs five steps automatically:
1. Starts the Coder server via Docker Compose
2. Creates an admin user and authenticates the CLI
3. Detects your Claude Code credentials and stores them in a swamp vault
4. Pushes the workspace template (builds the container image)
5. Creates a workspace with credentials resolved from the vault

### Credentials

`make bootstrap` looks for credentials in two places (in order):

1. **Shell environment** — checks for exported env vars
2. **`~/.claude/settings.json`** — reads the `env` object if vars aren't in the shell

| Provider | Variables |
|----------|-----------|
| Anthropic API | `ANTHROPIC_API_KEY` |
| AWS Bedrock | `CLAUDE_CODE_USE_BEDROCK` + `AWS_BEARER_TOKEN_BEDROCK` |

Credentials are stored in a local encrypted swamp vault (`sandbox-creds`) and
referenced via `${{ vault.get() }}` expressions. They never appear in plaintext
in model definitions, execution reports, or git history. The vault's encryption
key lives in `.swamp/secrets/` (gitignored).

Export your credentials before running, or ensure they're in your settings file:

```bash
# Option A: Anthropic API
export ANTHROPIC_API_KEY=sk-ant-...

# Option B: AWS Bedrock
export CLAUDE_CODE_USE_BEDROCK=1
export AWS_BEARER_TOKEN_BEDROCK=...
```

### Running tasks

Once the workspace is running, dispatch work via Coder tasks:

```bash
make task-inspect                          # Run the sandbox inspection example
make task PROMPT="your instructions here"  # Run a custom task
make tasks                                 # List running tasks
make status                                # Observe all infrastructure via swamp models
```

You can also SSH into the workspace directly:

```bash
make ssh
```

### Teardown

```bash
make destroy           # Delete workspace, stop server, remove all data
```

Or incrementally:

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

## Infrastructure as swamp models

The sandbox infrastructure is managed by four extension models in
`extensions/models/`:

| Model | Type | Purpose |
|-------|------|---------|
| coder-server | `sandbox/coder-server` | Docker Compose lifecycle (start/stop/status) |
| coder-template | `sandbox/coder-template` | Workspace template versioning |
| coder-workspace | `sandbox/coder-workspace` | Workspace provisioning and observation |
| coder-task | `sandbox/coder-task` | Task dispatch and log retrieval |

Each model produces typed, versioned data queryable with CEL:

```bash
# Observe all infrastructure state
make status

# Query workspace state directly
swamp data get coder-workspace current --json

# CEL query across all sandbox models
swamp data query 'modelType.startsWith("sandbox/") && isLatest == true' \
  --select '{"model": modelName, "spec": specName}' --json
```

Credentials flow through the vault — model definitions contain only
`${{ vault.get(sandbox-creds, KEY) }}` references, never plaintext values.

## Step-by-step guide

If you prefer to run commands directly without Make, this section walks through
each step using swamp models.

### 1. Start the Coder server

```bash
make up                # Docker Compose (auto-detects Docker or Podman socket)
```

Verify:

```bash
swamp model method run coder-server status
```

### 2. Authenticate

```bash
make login             # Creates admin user, authenticates CLI
```

### 3. Store credentials in the vault

```bash
make vault             # Detects credentials, stores in sandbox-creds vault
```

### 4. Create model instances and deploy

```bash
make models            # Creates swamp model instances with vault expressions
make setup             # Pushes template and creates workspace via models
```

Or run model methods directly:

```bash
swamp model method run coder-template push
swamp model method run coder-workspace create
```

### 5. Dispatch work

```bash
swamp model method run coder-task dispatch --input "prompt=Run swamp model method run sandbox-inspect execute"
```

Or SSH in:

```bash
make ssh
```

### Cleanup

```bash
swamp model method run coder-workspace delete   # Delete workspace via model
make down                                        # Stop Docker Compose
make reset                                       # Remove all data
```

## How it works

Docker Compose runs a Coder server that uses your host Docker daemon to
provision workspace containers. Each workspace is built from a Debian slim-based
image with Claude Code and swamp pre-installed. The image is multi-arch
(x86_64 and ARM).

Swamp models manage the full lifecycle: template push, workspace creation,
task dispatch, and status observation. Credentials are stored in a local
encrypted vault and resolved at runtime via CEL expressions — they never
appear in model definitions, execution logs, or reports.

No Kubernetes or cloud accounts required.

## Adding examples

Create a new directory under `examples/` following the naming convention
`NN-description/`. Add a README explaining the example and any model or
workflow definitions needed. See the existing examples for the pattern.
