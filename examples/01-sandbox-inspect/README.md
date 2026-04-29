# 01: Sandbox Inspection

This example creates a swamp model that inspects its own execution environment,
demonstrating that swamp is running inside an isolated Coder workspace container.

## What it does

The `sandbox-inspect` model runs system commands to report:

- Hostname and container ID
- Current user and permissions
- Available CLI tools (swamp, claude, git, jq)
- Network interfaces and connectivity
- Filesystem mounts and writable paths

The output makes it visually clear that execution is happening inside a
container, not on your host machine.

## Running the example

Make sure you have a Coder workspace running (see the root README for setup).

From your host machine, create a Coder task that runs the inspection:

```bash
coder tasks create my-sandbox \
  --command "cd /home/coder && swamp model method run sandbox-inspect inspect"
```

Or open a terminal in the Coder workspace and run it directly:

```bash
swamp model method run sandbox-inspect inspect
```

## Expected output

You should see container-specific values: a short hostname (not your machine's
name), the `coder` user, Alpine Linux paths, and container network interfaces.
This confirms swamp execution is sandboxed.
