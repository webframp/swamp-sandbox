# 06: Architect Loop

This example demonstrates the full agentic lifecycle: an AI agent that plans,
observes, reasons about what it sees, and acts — all within swamp's typed
guardrails. It is not a single model or workflow to run, but a task prompt
pattern that exercises everything from the previous examples together.

## What it demonstrates

The architect loop is the pattern from
[The Pipeline Is Dead](https://webframp.com/posts/the-pipeline-is-dead/):
"The agent should observe first, not generate more code faster." Rather than
generating declarations blindly, the agent queries reality, reasons about
whether to act, and produces typed data at every step.

The lifecycle:

1. **Plan** — Claude Code designs a model for a stated goal
2. **Observe** — runs existing models to understand current system state
3. **Decide** — uses CEL queries against versioned data to determine whether
   action is needed
4. **Act** — creates and executes the model only if the observation warrants it
5. **Verify** — queries the new output to confirm the action succeeded

This is the difference between "agents that write declarations faster" and
"agents that observe reality and reason about whether to act."

## Running the example

From the sandbox workspace, dispatch a task with the architect-loop prompt:

```bash
make task PROMPT="$(cat examples/06-architect-loop/prompt.md)"
```

Or SSH in and run Claude Code directly:

```bash
make ssh
claude "$(cat examples/06-architect-loop/prompt.md)"
```

Watch the agent work through each phase. It will:
- Inspect available model types and existing data
- Design a model for something that doesn't yet exist
- Check whether the observation has already been captured
- Execute only if the data is missing or stale
- Query its own output to verify the result

## The prompt

The file `prompt.md` contains the task prompt. It asks Claude Code to:

1. Search for existing models that capture container resource limits
2. If none exist, design and create one using `command/shell`
3. Run the model to observe current cgroup limits
4. Query the output and report whether the container is memory-constrained
5. Compare against any prior runs (if versioned data exists)

The key constraint: the agent must query before acting. It cannot skip
observation and jump straight to execution.

## Key concepts

- **Observation before action** — the agent checks existing state via
  `swamp data query` before creating anything new
- **Typed output as reasoning input** — the model produces structured JSON that
  the agent can reason about programmatically
- **Versioned comparison** — if run twice, the agent sees version history and
  can detect drift between runs
- **No static declarations** — the model is designed at runtime based on what
  the agent observes, not from a template file checked into the repo
- **Guardrails from the skill system** — Claude Code uses swamp skills to
  validate the model before execution, catching schema errors before they
  produce bad data

## Why this matters

Traditional automation: human writes declaration → tool applies it → hope state
matches. The tool is blind to whether the action was needed.

Architect loop: agent observes → reasons about gap between current and desired →
acts only when warranted → verifies the result. The agent sees reality at both
ends.

This is what "idempotency moves up the stack" means in practice. The model
method itself doesn't need complex idempotency logic — the agent decides whether
to call it at all by querying what already exists.

## Extending it

Try modifying `prompt.md` to ask for a different observation target:
- Network policy (what egress is allowed from this container?)
- Package versions (are any installed packages outdated?)
- File integrity (have any files changed since the image was built?)

The loop is identical regardless of domain. That's the point.

## Via Coder task

```bash
make task PROMPT="Follow the architect-loop pattern in examples/06-architect-loop/prompt.md: observe existing state, decide whether action is needed, create and run a model only if warranted, then verify the output"
```
