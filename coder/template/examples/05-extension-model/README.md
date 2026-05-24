# 05: Extension Model

This example demonstrates building a custom TypeScript model with a Zod schema.
It shows that swamp's primitives are domain-agnostic — the same machinery that
wraps Kubernetes APIs or AWS services works for any typed data you define.

## What it demonstrates

The `sandbox-sysinfo` extension model uses Node.js APIs (not shell commands) to
capture system information with full schema validation. The Zod schema defines
exactly what shape the output takes. If the data doesn't match the schema, the
method fails — you never get unvalidated data into the datastore.

This is the pattern from
[Swamp Beyond Infrastructure](https://webframp.com/posts/swamp-beyond-infrastructure/):
"Schema in. Validated data out. Versioned and queryable. Composable into DAGs.
Those four properties do not privilege any domain."

## The extension structure

```
extensions/models/sandbox-sysinfo/
  manifest.yaml   # Extension metadata (name, type, version, platforms)
  mod.ts          # TypeScript implementation with Zod schema
```

## Running the example

From the sandbox workspace:

```bash
# The extension type is available because it lives in extensions/models/
swamp model type search sysinfo --json

# Describe the type to see its schema and methods
swamp model type describe sandbox/sysinfo --json

# Create a model instance
swamp model create sandbox/sysinfo my-sysinfo --json

# Run the collect method
swamp model method run my-sysinfo collect

# View the validated output
swamp model output get my-sysinfo --json

# The output is queryable like any other model data
swamp data query 'modelName == "my-sysinfo" && isLatest == true' --json
```

## Key concepts

- **Zod schema as contract** — the schema defines both the validation rules and
  the queryable output shape
- **Same CLI, any domain** — `swamp model method run` works identically whether
  the model wraps kubectl, an HTTP API, or Node.js built-ins
- **No shell parsing** — the model produces structured data directly, no jq or
  awk needed
- **Composable** — this model's output can be consumed by workflows, CEL queries,
  or other models just like any command/shell model

## Extending it

Try adding a new method to `mod.ts`. For example, a `compare` method that reads
the two most recent versions and reports what changed. The pattern is:
1. Add a new key to the `methods` object
2. Define its `inputs` and `dataOutputSpecs`
3. Implement `execute()`

No registration step. No configuration change. The CLI picks it up automatically.

## Via Coder task

```bash
make task PROMPT="Look at the sandbox-sysinfo extension in extensions/models/, create a model from it, run the collect method, and explain how the Zod schema validates the output"
```
