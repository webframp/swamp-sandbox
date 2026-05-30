// ABOUTME: Polls Coder server health and build info endpoints.
// ABOUTME: Produces typed, versioned health state for burn-in reliability analysis.
import { z } from "npm:zod@4";

const GlobalArgsSchema = z.object({
  url: z.string().url().default("http://localhost:3000"),
});

const HealthProbeSchema = z.object({
  healthy: z.boolean(),
  status: z.enum(["reachable", "unhealthy", "unreachable"]),
  version: z.string().optional(),
  healthzLatencyMs: z.number(),
  buildinfoLatencyMs: z.number(),
  checkedAt: z.string(),
  error: z.string().optional(),
});

async function timedFetch(
  url: string,
  timeoutMs: number = 5000,
): Promise<{ ok: boolean; latencyMs: number; body?: unknown; error?: string }> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  const start = performance.now();

  try {
    const res = await fetch(url, { signal: controller.signal });
    const latencyMs = Math.round(performance.now() - start);
    clearTimeout(timeout);

    if (res.ok) {
      const body = await res.json();
      return { ok: true, latencyMs, body };
    }
    return { ok: false, latencyMs, error: `HTTP ${res.status}` };
  } catch (err) {
    clearTimeout(timeout);
    const latencyMs = Math.round(performance.now() - start);
    return { ok: false, latencyMs, error: String(err) };
  }
}

export const model = {
  type: "burn-in/health-probe",
  version: "2026.05.30.1",
  description:
    "Polls Coder server health and build info endpoints. Produces typed health state for burn-in analysis.",
  globalArguments: GlobalArgsSchema,
  resources: {
    probe: {
      description: "Health probe result with latency measurements",
      schema: HealthProbeSchema,
      lifetime: "infinite" as const,
      garbageCollection: 100,
    },
  },
  methods: {
    check: {
      description: "Probe server health and record result",
      arguments: z.object({}),
      execute: async (_args: Record<string, unknown>, context: any) => {
        const url = context.globalArgs.url;
        context.logger.info("Probing health at {url}", { url });

        const healthz = await timedFetch(`${url}/healthz`);
        const buildinfo = await timedFetch(`${url}/api/v2/buildinfo`);

        let status: "reachable" | "unhealthy" | "unreachable";
        if (healthz.ok && buildinfo.ok) {
          status = "reachable";
        } else if (healthz.ok || buildinfo.ok) {
          status = "unhealthy";
        } else {
          status = "unreachable";
        }

        const version =
          buildinfo.body && typeof buildinfo.body === "object"
            ? (buildinfo.body as Record<string, unknown>).version as string
            : undefined;

        const probe = {
          healthy: status === "reachable",
          status,
          version,
          healthzLatencyMs: healthz.latencyMs,
          buildinfoLatencyMs: buildinfo.latencyMs,
          checkedAt: new Date().toISOString(),
          error: healthz.error || buildinfo.error || undefined,
        };

        context.logger.info("Probe result: {status} (healthz={hMs}ms, buildinfo={bMs}ms)", {
          status,
          hMs: healthz.latencyMs,
          bMs: buildinfo.latencyMs,
        });

        const handle = await context.writeResource("probe", "current", probe);
        return { dataHandles: [handle] };
      },
    },
  },
};
