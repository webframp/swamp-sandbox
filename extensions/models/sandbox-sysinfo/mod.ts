import { z } from "zod";

const SysinfoSchema = z.object({
  hostname: z.string(),
  platform: z.string(),
  arch: z.string(),
  kernelVersion: z.string(),
  nodeVersion: z.string(),
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
    "Captures structured system information from the sandbox container using Node.js APIs. Demonstrates building a typed extension model with Zod schema validation.",
  globalArguments: z.object({}),
  methods: {
    collect: {
      description:
        "Collect system information and return as validated typed data",
      inputs: z.object({}),
      dataOutputSpecs: [
        {
          specName: "info",
          kind: "resource" as const,
          description: "Validated system information snapshot",
          schema: SysinfoSchema,
          lifetime: "infinite" as const,
          garbageCollection: 5,
        },
      ],
      async execute(_args: Record<string, unknown>) {
        const os = await import("node:os");
        const { execSync } = await import("node:child_process");

        const totalMem = os.totalmem() / 1024 / 1024;
        const freeMem = os.freemem() / 1024 / 1024;

        let swampVersion: string | undefined;
        try {
          swampVersion = execSync("swamp --version", { encoding: "utf-8" }).trim();
        } catch {
          swampVersion = undefined;
        }

        const info = {
          hostname: os.hostname(),
          platform: os.platform(),
          arch: os.arch(),
          kernelVersion: os.release(),
          nodeVersion: process.version,
          uptimeSeconds: Math.floor(os.uptime()),
          memoryMB: {
            total: Math.round(totalMem),
            free: Math.round(freeMem),
            usedPercent: Math.round(((totalMem - freeMem) / totalMem) * 100),
          },
          cpuCount: os.cpus().length,
          environment: {
            user: os.userInfo().username,
            home: os.homedir(),
            shell: os.userInfo().shell || "/bin/sh",
            ...(swampVersion ? { swampVersion } : {}),
          },
        };

        return {
          data: [{ specName: "info", data: info }],
        };
      },
    },
  },
};
