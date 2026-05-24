# 04: Workflow DAG

This example demonstrates swamp workflows: a directed acyclic graph of parallel
jobs that observe different aspects of the system, then a synthesis step that
queries all results and produces a combined verdict.

## What it demonstrates

The `sandbox-health` workflow runs three observation jobs in parallel:
- **observe-filesystem** — disk usage, file counts, writable paths
- **observe-network** — interfaces, listening ports, DNS, connectivity
- **observe-processes** — process counts, top CPU/memory consumers

A fourth job (**synthesize**) depends on all three completing successfully. It
reads the environment and produces a health verdict.

This is the pattern from
[The Pipeline Is Dead](https://webframp.com/posts/the-pipeline-is-dead/):
concurrent agents with shared state replace sequential handoffs.

## Running the example

From the sandbox workspace:

```bash
# Validate the workflow definition
swamp workflow validate sandbox-health

# Run the workflow
swamp workflow run sandbox-health

# View run history
swamp workflow history sandbox-health --json

# Query all outputs produced by the workflow's models
swamp data query 'tags.example == "04-workflow-dag" && isLatest == true' --json
```

## Key concepts

- **Parallel execution** — the three observation jobs start simultaneously, not
  sequentially
- **Dependency conditions** — the synthesis job only runs after all three
  observers succeed
- **Shared data layer** — each job writes typed output that other jobs (or
  future queries) can read
- **No handoffs** — no tickets filed, no queues, no waiting for a human to
  bridge concerns
- **Composable** — add a new observation job without touching the others

## The pipeline this replaces

In a traditional CI/CD pipeline, these checks run sequentially: filesystem
health blocks network check blocks process audit blocks the final report. Each
transition is a handoff. Wait time is the dominant cost.

In the workflow DAG, the only real dependency is that the synthesis step needs
all observations complete. Everything else runs concurrently because nothing
actually depends on anything else.

## Via Coder task

```bash
make task PROMPT="Run the sandbox-health workflow and show me the results from all four jobs, explaining how the parallel execution worked"
```
