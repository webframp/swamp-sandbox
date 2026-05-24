/**
 * Captures structured system information using Deno APIs with full Zod
 * schema validation. Demonstrates domain-agnostic model primitives.
 *
 * @module
 */
import { z } from "npm:zod@4";

const SysinfoSchema = z.object({
  hostname: z.string(),
  platform: z.string(),
  arch: z.string(),
  kernelVersion: z.string(),
  denoVersion: z.string(),
  uptimeSeconds: z.number().int().nonnegative(),
  memoryMB: z.object({
    total: z.number().nonnegative(),
    free: z.number().nonnegative(),
    usedPercent: z.number().min(0).max(100),
  }),
  cpuCount: z.number().int().positive(),
  environment: z.object({
    user: z.string(),
    home: z.string(),
    shell: z.string(),
    swampVersion: z.string().optional(),
  }),
});

export const model = {
  type: "sandbox/sysinfo",
  version: "2026.05.24.1",
  description:
    "Captures structured system information using Deno APIs. Demonstrates building a typed extension model with Zod schema validation.",
  globalArguments: z.object({}),
  resources: {
    info: {
      description: "Validated system information snapshot",
      schema: SysinfoSchema,
      lifetime: "infinite" as const,
      garbageCollection: 5,
    },
  },
  methods: {
    collect: {
      description:
        "Collect system information and return as validated typed data",
      arguments: z.object({}),
      execute: async (_args: Record<string, unknown>, context: any) => {
        const hostname = Deno.hostname();
        const osRelease = Deno.osRelease();
        const memInfo = Deno.systemMemoryInfo();
        const totalMem = memInfo.total / 1024 / 1024;
        const freeMem = memInfo.free / 1024 / 1024;

        let swampVersion: string | undefined;
        try {
          const cmd = new Deno.Command("swamp", {
            args: ["--version"],
            stdout: "piped",
            stderr: "piped",
          });
          const output = await cmd.output();
          if (output.success) {
            swampVersion = new TextDecoder().decode(output.stdout).trim();
          }
        } catch {
          swampVersion = undefined;
        }

        const info = {
          hostname,
          platform: Deno.build.os,
          arch: Deno.build.arch,
          kernelVersion: osRelease,
          denoVersion: Deno.version.deno,
          uptimeSeconds: Math.floor(performance.now() / 1000),
          memoryMB: {
            total: Math.round(totalMem),
            free: Math.round(freeMem),
            usedPercent: Math.round(((totalMem - freeMem) / totalMem) * 100),
          },
          cpuCount: navigator.hardwareConcurrency,
          environment: {
            user: Deno.env.get("USER") || Deno.env.get("USERNAME") || "unknown",
            home: Deno.env.get("HOME") || Deno.env.get("USERPROFILE") || "/",
            shell: Deno.env.get("SHELL") || "/bin/sh",
            ...(swampVersion ? { swampVersion } : {}),
          },
        };

        const handle = await context.writeResource("info", "current", info);
        return { dataHandles: [handle] };
      },
    },
  },
};
