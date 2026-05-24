/**
 * Manages the Coder server lifecycle via Docker Compose.
 *
 * @module
 */
import { z } from "npm:zod@4";

const GlobalArgsSchema = z.object({
  url: z.string().url().default("http://localhost:3000"),
  composeFile: z.string().default("docker-compose.yaml"),
});

const ServerStateSchema = z.object({
  status: z.enum(["running", "stopped", "starting", "unhealthy"]),
  url: z.string().url(),
  version: z.string().optional(),
  containerId: z.string().optional(),
  containerImage: z.string().optional(),
  uptime: z.string().optional(),
  checkedAt: z.string(),
});

type ServerState = z.infer<typeof ServerStateSchema>;

async function runCommand(
  cmd: string,
  args: string[],
): Promise<{ success: boolean; stdout: string; stderr: string }> {
  const command = new Deno.Command(cmd, {
    args,
    stdout: "piped",
    stderr: "piped",
  });
  const output = await command.output();
  return {
    success: output.success,
    stdout: new TextDecoder().decode(output.stdout).trim(),
    stderr: new TextDecoder().decode(output.stderr).trim(),
  };
}

async function getServerStatus(url: string): Promise<Partial<ServerState>> {
  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 5000);
    const res = await fetch(`${url}/api/v2/buildinfo`, {
      signal: controller.signal,
    });
    clearTimeout(timeout);

    if (res.ok) {
      const info = await res.json();
      return {
        status: "running",
        version: info.version,
      };
    }
    return { status: "unhealthy" };
  } catch {
    return { status: "stopped" };
  }
}

async function getContainerInfo(): Promise<{
  id?: string;
  image?: string;
  uptime?: string;
}> {
  const result = await runCommand("docker", [
    "ps",
    "--filter",
    "name=coder",
    "--format",
    "{{json .}}",
  ]);
  if (!result.success || !result.stdout) return {};

  try {
    const lines = result.stdout.split("\n").filter(Boolean);
    const container = JSON.parse(lines[0]);
    return {
      id: (container.ID || container.Id || "").slice(0, 12),
      image: container.Image,
      uptime: container.RunningFor || container.Status,
    };
  } catch {
    return {};
  }
}

export const model = {
  type: "sandbox/coder-server",
  version: "2026.05.24.1",
  description:
    "Manages the Coder server lifecycle via Docker Compose. Observes server health, version, and container state as typed versioned data.",
  globalArguments: GlobalArgsSchema,
  resources: {
    state: {
      description:
        "Current server state including health, version, and container info",
      schema: ServerStateSchema,
      lifetime: "infinite" as const,
      garbageCollection: 10,
    },
  },
  methods: {
    start: {
      description:
        "Start the Coder server via Docker Compose and wait for it to become healthy",
      arguments: z.object({
        containerSocket: z
          .string()
          .default("/var/run/docker.sock"),
      }),
      execute: async (args: Record<string, unknown>, context: any) => {
        const url = context.globalArgs.url;
        const socket = (args as { containerSocket: string }).containerSocket;

        context.logger.info("Starting Coder server with socket {socket}", {
          socket,
        });

        const startResult = await runCommand("docker", [
          "compose",
          "up",
          "-d",
        ]);

        if (!startResult.success) {
          throw new Error(`Failed to start: ${startResult.stderr}`);
        }

        // Wait for server to become healthy
        let serverState: Partial<ServerState> = { status: "starting" };
        for (let i = 0; i < 15; i++) {
          await new Promise((r) => setTimeout(r, 2000));
          serverState = await getServerStatus(url);
          if (serverState.status === "running") break;
        }

        if (serverState.status !== "running") {
          throw new Error("Server did not become healthy within 30 seconds");
        }

        const containerInfo = await getContainerInfo();

        const state: ServerState = {
          status: "running",
          url,
          version: serverState.version,
          containerId: containerInfo.id,
          containerImage: containerInfo.image,
          uptime: containerInfo.uptime,
          checkedAt: new Date().toISOString(),
        };

        const handle = await context.writeResource("state", "current", state);
        return { dataHandles: [handle] };
      },
    },
    stop: {
      description: "Stop the Coder server via Docker Compose",
      arguments: z.object({}),
      execute: async (_args: Record<string, unknown>, context: any) => {
        context.logger.info("Stopping Coder server");

        const result = await runCommand("docker", ["compose", "down"]);

        if (!result.success) {
          throw new Error(`Failed to stop: ${result.stderr}`);
        }

        const state: ServerState = {
          status: "stopped",
          url: context.globalArgs.url,
          checkedAt: new Date().toISOString(),
        };

        const handle = await context.writeResource("state", "current", state);
        return { dataHandles: [handle] };
      },
    },
    status: {
      description: "Observe current server health without modifying state",
      arguments: z.object({}),
      execute: async (_args: Record<string, unknown>, context: any) => {
        const url = context.globalArgs.url;

        context.logger.info("Checking server status at {url}", { url });

        const serverState = await getServerStatus(url);
        const containerInfo = await getContainerInfo();

        const state: ServerState = {
          status: serverState.status || "stopped",
          url,
          version: serverState.version,
          containerId: containerInfo.id,
          containerImage: containerInfo.image,
          uptime: containerInfo.uptime,
          checkedAt: new Date().toISOString(),
        };

        const handle = await context.writeResource("state", "current", state);
        return { dataHandles: [handle] };
      },
    },
  },
};
