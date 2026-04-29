# swamp-sandbox

A practical demo of sandboxing [swamp](https://swamp.club) execution inside
[Coder](https://coder.com) workspaces using Docker Compose.

Claude Code + swamp run inside isolated containers managed by Coder, keeping
agent execution separate from your host environment. This repo demonstrates
the pattern and provides examples you can build on.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) and Docker Compose (or Podman)
- [Coder CLI](https://coder.com/docs/install)
- An [Anthropic API key](https://console.anthropic.com/)
- Make

Works on Linux (x86_64 and ARM), macOS (Apple Silicon and Intel), and WSL2.

## Quickstart

Three commands to go from clone to running sandbox:

```bash
make up                # Start the Coder server
make login             # Create admin user and authenticate CLI (fully automatic)
make setup             # Push template and create workspace (prompts for API key)
```

`make login` creates a default admin account and authenticates the CLI
without any browser interaction. `make setup` prompts for your Anthropic API
key, then builds the workspace image and creates the sandbox.

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
coder create my-sandbox --template sandbox \
  --parameter anthropic_api_key=YOUR_API_KEY_HERE \
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
