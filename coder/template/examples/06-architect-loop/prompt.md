You are working inside a sandboxed container. Your goal is to determine whether
this container is memory-constrained by observing its cgroup resource limits.
Follow the architect loop — observe before you act.

## Phase 1: Observe existing state

Search for any existing models or data that already capture container resource
limits:

```
swamp model search --json
swamp data query 'specName == "result" && attributes.cgroups != null' --json
```

If relevant data already exists and is recent (check the version timestamp),
report what you found and skip to Phase 4.

## Phase 2: Design the model

If no existing data covers cgroup limits, create a command/shell model named
`container-limits` that captures:
- Memory limit from `/sys/fs/cgroup/memory.max` (or memory.limit_in_bytes)
- Memory current usage from `/sys/fs/cgroup/memory.current`
- CPU quota from `/sys/fs/cgroup/cpu.max`
- Number of available CPUs from `/sys/fs/cgroup/cpu.max` or nproc
- Whether swap is limited

The shell command must output structured JSON. Validate the model before
running it.

## Phase 3: Execute

Run the model method and confirm it succeeds:

```
swamp model method run container-limits execute
```

## Phase 4: Verify and reason

Query the output and answer these questions:
1. What is the memory limit for this container?
2. What percentage of memory is currently in use?
3. Is the container CPU-throttled (quota < period × nproc)?
4. Would you recommend increasing any limits for running AI workloads?

Use `swamp model output get container-limits --json` to retrieve the structured
result. Base your reasoning on the typed data, not on assumptions.

## Phase 5: Compare (if applicable)

If this model has been run before (version > 1), compare the current observation
against the previous one:

```
swamp data query 'modelName == "container-limits"' --json
```

Report any drift in resource allocation between versions.
