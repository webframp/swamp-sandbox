/**
 * Manages Coder workspace lifecycle via the Coder REST API.
 *
 * @module
 */
import { z } from "npm:zod@4";

const GlobalArgsSchema = z.object({
  url: z.string().url().default("http://localhost:3000"),
  templateName: z.string().default("sandbox"),
  workspaceName: z.string().default("my-sandbox"),
  claudeProvider: z.string().default("bedrock"),
  anthropicApiKey: z.string().default(""),
  awsBearerTokenBedrock: z.string().default(""),
  claudeCodeUseBedrock: z.string().default(""),
  awsRegion: z.string().default("us-east-1"),
});

const WorkspaceStateSchema = z.object({
  id: z.string().optional(),
  name: z.string(),
  templateName: z.string(),
  status: z.enum([
    "running",
    "stopped",
    "starting",
    "stopping",
    "failed",
    "deleted",
    "not_found",
  ]),
  latestBuildStatus: z.string().optional(),
  agentStatus: z.string().optional(),
  createdAt: z.string().optional(),
  lastUsedAt: z.string().optional(),
  checkedAt: z.string(),
});

async function getSessionToken(): Promise<string | null> {
  const configDir = Deno.env.get("CODER_CONFIG_DIR") ||
    `${Deno.env.get("HOME")}/.config/coderv2`;
  try {
    const session = await Deno.readTextFile(`${configDir}/session`);
    return session.trim();
  } catch {
    return null;
  }
}

async function coderApi(
  url: string,
  path: string,
  token: string,
  options?: { method?: string; body?: unknown },
): Promise<{ ok: boolean; status: number; data: any }> {
  const res = await fetch(`${url}${path}`, {
    method: options?.method || "GET",
    headers: {
      "Coder-Session-Token": token,
      Accept: "application/json",
      ...(options?.body ? { "Content-Type": "application/json" } : {}),
    },
    ...(options?.body ? { body: JSON.stringify(options.body) } : {}),
  });
  const data = res.ok ? await res.json() : null;
  return { ok: res.ok, status: res.status, data };
}

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

async function findCoderBin(): Promise<string> {
  const repoLocal = `${Deno.cwd()}/.local/bin/coder`;
  try {
    await Deno.stat(repoLocal);
    return repoLocal;
  } catch {
    return "coder";
  }
}

export const model = {
  type: "sandbox/coder-workspace",
  version: "2026.05.24.1",
  description:
    "Manages Coder workspace lifecycle. Create, delete, and observe workspace state as typed versioned data.",
  globalArguments: GlobalArgsSchema,
  resources: {
    state: {
      description:
        "Current workspace state including status, agent connectivity, and build info",
      schema: WorkspaceStateSchema,
      lifetime: "infinite" as const,
      garbageCollection: 10,
    },
  },
  methods: {
    create: {
      description:
        "Create a new workspace from the configured template with Claude Code credentials from vault",
      arguments: z.object({}),
      execute: async (_args: Record<string, unknown>, context: any) => {
        const {
          url,
          templateName,
          workspaceName,
          claudeProvider,
          anthropicApiKey,
          awsBearerTokenBedrock,
          claudeCodeUseBedrock,
          awsRegion,
        } = context.globalArgs;

        context.logger.info("Creating workspace {name} from template {template}", {
          name: workspaceName,
          template: templateName,
        });

        const coderBin = await findCoderBin();
        const cliArgs = [
          "create",
          workspaceName,
          "--template",
          templateName,
          "--parameter",
          "AI Prompt=",
          "--parameter",
          `claude_provider=${claudeProvider}`,
          "--parameter",
          `anthropic_api_key=${anthropicApiKey}`,
          "--parameter",
          `aws_bearer_token_bedrock=${awsBearerTokenBedrock}`,
          "--parameter",
          `claude_code_use_bedrock=${claudeCodeUseBedrock}`,
          "--parameter",
          `aws_region=${awsRegion}`,
          "--yes",
        ];

        const result = await runCommand(coderBin, cliArgs);

        if (!result.success) {
          throw new Error(`Workspace creation failed: ${result.stderr}`);
        }

        // Fetch workspace state from API
        const token = await getSessionToken();
        if (!token) {
          throw new Error("No Coder session token found");
        }

        const wsRes = await coderApi(
          url,
          `/api/v2/users/me/workspace/${workspaceName}`,
          token,
        );

        const state = {
          id: wsRes.data?.id,
          name: workspaceName,
          templateName,
          status: mapWorkspaceStatus(wsRes.data?.latest_build?.status),
          latestBuildStatus: wsRes.data?.latest_build?.status,
          agentStatus: wsRes.data?.latest_build?.resources?.[0]?.agents?.[0]
            ?.status,
          createdAt: wsRes.data?.created_at,
          lastUsedAt: wsRes.data?.last_used_at,
          checkedAt: new Date().toISOString(),
        };

        const handle = await context.writeResource("state", "current", state);
        return { dataHandles: [handle] };
      },
    },
    delete: {
      description: "Delete the workspace and clean up resources",
      arguments: z.object({
        orphan: z.boolean().default(true),
      }),
      execute: async (args: Record<string, unknown>, context: any) => {
        const { workspaceName } = context.globalArgs;
        const typedArgs = args as { orphan: boolean };

        context.logger.info("Deleting workspace {name}", { name: workspaceName });

        const coderBin = await findCoderBin();
        const cliArgs = ["delete", workspaceName, "--yes"];
        if (typedArgs.orphan) {
          cliArgs.push("--orphan");
        }

        const result = await runCommand(coderBin, cliArgs);

        if (!result.success && !result.stderr.includes("not found")) {
          throw new Error(`Workspace deletion failed: ${result.stderr}`);
        }

        const state = {
          name: workspaceName,
          templateName: context.globalArgs.templateName,
          status: "deleted" as const,
          checkedAt: new Date().toISOString(),
        };

        const handle = await context.writeResource("state", "current", state);
        return { dataHandles: [handle] };
      },
    },
    status: {
      description: "Observe current workspace state from the Coder API",
      arguments: z.object({}),
      execute: async (_args: Record<string, unknown>, context: any) => {
        const { url, workspaceName, templateName } = context.globalArgs;

        const token = await getSessionToken();
        if (!token) {
          throw new Error("No Coder session token found");
        }

        const wsRes = await coderApi(
          url,
          `/api/v2/users/me/workspace/${workspaceName}`,
          token,
        );

        if (!wsRes.ok) {
          const state = {
            name: workspaceName,
            templateName,
            status: "not_found" as const,
            checkedAt: new Date().toISOString(),
          };
          const handle = await context.writeResource("state", "current", state);
          return { dataHandles: [handle] };
        }

        const state = {
          id: wsRes.data.id,
          name: workspaceName,
          templateName,
          status: mapWorkspaceStatus(wsRes.data.latest_build?.status),
          latestBuildStatus: wsRes.data.latest_build?.status,
          agentStatus: wsRes.data.latest_build?.resources?.[0]?.agents?.[0]
            ?.status,
          createdAt: wsRes.data.created_at,
          lastUsedAt: wsRes.data.last_used_at,
          checkedAt: new Date().toISOString(),
        };

        const handle = await context.writeResource("state", "current", state);
        return { dataHandles: [handle] };
      },
    },
  },
};

function mapWorkspaceStatus(
  buildStatus: string | undefined,
): "running" | "stopped" | "starting" | "stopping" | "failed" | "deleted" | "not_found" {
  switch (buildStatus) {
    case "running":
      return "running";
    case "succeeded":
      return "running";
    case "starting":
      return "starting";
    case "stopping":
      return "stopping";
    case "failed":
      return "failed";
    case "canceled":
      return "stopped";
    default:
      return "stopped";
  }
}
