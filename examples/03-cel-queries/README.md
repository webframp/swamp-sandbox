# 03: CEL Queries

This example demonstrates querying model output with Common Expression Language
(CEL). Once data is typed and versioned, you compose against it with expressions
rather than re-running commands or parsing text.

## What it demonstrates

After running the `sandbox-observe` model from example 02, the output lives as
queryable data in swamp's datastore. CEL expressions let you filter, select, and
compare across all versioned data — the same query language works regardless of
whether the data came from shell output, an API call, or a TypeScript extension.

This is the pattern from
[The Pipeline Is Dead](https://webframp.com/posts/the-pipeline-is-dead/):
"The data is the meeting. The query is the vote."

## Running the example

Prerequisites: run example 02 at least twice to have multiple versions.

```bash
# Query the latest observation
swamp data query 'modelName == "sandbox-observe" && isLatest == true' --json

# Query all versions (see drift over time)
swamp data query 'modelName == "sandbox-observe"' --json

# Select specific fields from the latest output
swamp data query 'modelName == "sandbox-observe" && isLatest == true' \
  --select '{"host": attributes.hostname, "packages": attributes.stdout}' --json

# Query across multiple models (sandbox-inspect + sandbox-observe)
swamp data query 'specName == "result" && isLatest == true' --json

# Filter by version number
swamp data query 'modelName == "sandbox-observe" && version == 1' --json
```

## Key concepts

- **CEL is the composition layer** — models produce data, CEL queries consume it
- **Cross-model queries** — one query can span output from any model in the repo
- **Version-aware** — query the latest, a specific version, or all versions
- **Field selection** — extract exactly the fields you need with `--select`
- **No re-execution needed** — once data exists, query it without re-running the
  method that produced it

## The pattern in practice

In production swamp workflows, CEL queries replace:
- Dashboard queries against monitoring systems
- Manual inspection of command output
- Cross-referencing data from different tools
- Change advisory board meetings (the data is the meeting, the query is the vote)

## Via Coder task

```bash
make task PROMPT="Run sandbox-observe execute twice, then show me all CEL queries I can run against the output — demonstrate filtering, version comparison, and field selection"
```
