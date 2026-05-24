# 02: Typed Observation

This example demonstrates swamp's core primitive: observing a live system and
storing the result as typed, versioned, schema-validated data.

## What it demonstrates

The `sandbox-observe` model runs a shell command that captures structured
information about the container environment — installed packages, running
processes, open ports, disk usage — and outputs it as JSON. Swamp stores each
execution as a new version. Run it twice and you can see exactly what changed.

This is the pattern described in
[You Were Never Declaring State](https://webframp.com/posts/you-were-never-declaring-state/):
the agent observes reality directly and stores typed snapshots. No declaration
file needed.

## Running the example

From the sandbox workspace:

```bash
# First observation
swamp model method run sandbox-observe execute

# View the stored data
swamp model output get sandbox-observe --json

# Make a change (install a package, create a file, start a process)
touch /tmp/drift-marker
echo "something changed" > /tmp/new-file

# Second observation — creates version 2
swamp model method run sandbox-observe execute

# Compare versions with a CEL query (see example 03 for more)
swamp data query 'modelName == "sandbox-observe" && isLatest == true' --json
```

## Key concepts

- **Observation over declaration** — the model captures what exists, not what
  should exist
- **Versioned data** — every execution creates a new immutable version
- **Typed output** — the JSON output conforms to a known structure, making it
  queryable
- **Drift detection** — compare version N to version N-1 to see what changed

## Via Coder task

```bash
make task PROMPT="Run 'swamp model method run sandbox-observe execute' twice with a 5 second gap, then show me both versions of the output"
```
