/**
 * Manages Coder workspace templates via the Coder REST API.
 *
 * @module
 */
import { z } from "npm:zod@4";

const GlobalArgsSchema = z.object({
  url: z.string().url().default("http://localhost:3000"),
  templateName: z.string().default("sandbox"),
  templateDir: z.string().default("./coder/template"),
  claudeProvider: z.string().default("bedrock"),
  anthropicApiKey: z.string().default(""),
  awsBearerTokenBedrock: z.string().default(""),
  claudeCodeUseBedrock: z.string().default(""),
  awsRegion: z.string().default("us-east-1"),
});

const TemplateStateSchema = z.object({
  id: z.string().optional(),
  name: z.string(),
  activeVersionId: z.string().optional(),
  activeVersionName: z.string().optional(),
  createdAt: z.string().optional(),
  updatedAt: z.string().optional(),
  buildStatus: z.enum(["succeeded", "failed", "pending", "unknown"]),
  parameterCount: z.number().int().nonnegative().optional(),
  workspaceCount: z.number().int().nonnegative().optional(),
  checkedAt: z.string(),
});

const VersionHistorySchema = z.object({
  templateName: z.string(),
  versions: z.array(
    z.object({
      id: z.string(),
      name: z.string(),
      createdAt: z.string(),
      createdBy: z.string().optional(),
      status: z.string(),
    }),
  ),
  checkedAt: z.string(),
});

async function getSessionToken(_url: string): Promise<string | null> {
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
): Promise<{ ok: boolean; status: number; data: any }> {
  const res = await fetch(`${url}${path}`, {
    headers: {
      "Coder-Session-Token": token,
      Accept: "application/json",
    },
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

export const model = {
  type: "sandbox/coder-template",
  version: "2026.05.24.1",
  description:
    "Manages Coder workspace templates. Push new versions, describe current state, and view version history as typed data.",
  globalArguments: GlobalArgsSchema,
  resources: {
    state: {
      description: "Current template state including version and build status",
      schema: TemplateStateSchema,
      lifetime: "infinite" as const,
      garbageCollection: 10,
    },
    versions: {
      description: "Template version history",
      schema: VersionHistorySchema,
      lifetime: "infinite" as const,
      garbageCollection: 5,
    },
  },
  methods: {
    push: {
      description:
        "Push a new template version to the Coder server with Claude Code credentials from vault. Uses the Coder CLI for the Terraform packaging step.",
      arguments: z.object({}),
      execute: async (_args: Record<string, unknown>, context: any) => {
        const {
          url,
          templateName,
          templateDir,
          claudeProvider,
          anthropicApiKey,
          awsBearerTokenBedrock,
          claudeCodeUseBedrock,
          awsRegion,
        } = context.globalArgs;

        context.logger.info("Pushing template {name} from {dir}", {
          name: templateName,
          dir: templateDir,
        });

        const cliArgs = [
          "templates",
          "push",
          templateName,
          "--directory",
          templateDir,
          "--yes",
          "--variable",
          `preset_claude_provider=${claudeProvider}`,
          "--variable",
          `preset_anthropic_api_key=${anthropicApiKey}`,
          "--variable",
          `preset_aws_bearer_token_bedrock=${awsBearerTokenBedrock}`,
          "--variable",
          `preset_claude_code_use_bedrock=${claudeCodeUseBedrock}`,
          "--variable",
          `preset_aws_region=${awsRegion}`,
        ];

        const coderBin = await findCoderBin();
        const result = await runCommand(coderBin, cliArgs);

        if (!result.success) {
          throw new Error(`Template push failed: ${result.stderr}`);
        }

        context.logger.info("Template push succeeded, fetching state");

        // Fetch updated template state from API
        const token = await getSessionToken(url);
        if (!token) {
          throw new Error(
            "No Coder session token found. Run login first.",
          );
        }

        const orgRes = await coderApi(
          url,
          "/api/v2/users/me/organizations",
          token,
        );
        const orgId = orgRes.data?.[0]?.id;

        const templateRes = await coderApi(
          url,
          `/api/v2/organizations/${orgId}/templates/${templateName}`,
          token,
        );

        const state = {
          id: templateRes.data?.id,
          name: templateName,
          activeVersionId: templateRes.data?.active_version_id,
          activeVersionName: templateRes.data?.active_version_name,
          createdAt: templateRes.data?.created_at,
          updatedAt: templateRes.data?.updated_at,
          buildStatus: templateRes.ok ? "succeeded" : "unknown",
          workspaceCount: templateRes.data?.workspace_owner_count,
          checkedAt: new Date().toISOString(),
        };

        const handle = await context.writeResource("state", "current", state);
        return { dataHandles: [handle] };
      },
    },
    describe: {
      description:
        "Describe the current template state from the Coder API without modifying anything",
      arguments: z.object({}),
      execute: async (_args: Record<string, unknown>, context: any) => {
        const { url, templateName } = context.globalArgs;

        const token = await getSessionToken(url);
        if (!token) {
          throw new Error("No Coder session token found. Run login first.");
        }

        const orgRes = await coderApi(
          url,
          "/api/v2/users/me/organizations",
          token,
        );
        const orgId = orgRes.data?.[0]?.id;

        const templateRes = await coderApi(
          url,
          `/api/v2/organizations/${orgId}/templates/${templateName}`,
          token,
        );

        if (!templateRes.ok) {
          throw new Error(
            `Template '${templateName}' not found (HTTP ${templateRes.status})`,
          );
        }

        const state = {
          id: templateRes.data.id,
          name: templateRes.data.name,
          activeVersionId: templateRes.data.active_version_id,
          activeVersionName: templateRes.data.active_version_name,
          createdAt: templateRes.data.created_at,
          updatedAt: templateRes.data.updated_at,
          buildStatus: "succeeded" as const,
          workspaceCount: templateRes.data.workspace_owner_count,
          checkedAt: new Date().toISOString(),
        };

        const handle = await context.writeResource("state", "current", state);
        return { dataHandles: [handle] };
      },
    },
    versions: {
      description: "List template version history",
      arguments: z.object({}),
      execute: async (_args: Record<string, unknown>, context: any) => {
        const { url, templateName } = context.globalArgs;

        const token = await getSessionToken(url);
        if (!token) {
          throw new Error("No Coder session token found. Run login first.");
        }

        const orgRes = await coderApi(
          url,
          "/api/v2/users/me/organizations",
          token,
        );
        const orgId = orgRes.data?.[0]?.id;

        const templateRes = await coderApi(
          url,
          `/api/v2/organizations/${orgId}/templates/${templateName}`,
          token,
        );

        if (!templateRes.ok) {
          throw new Error(
            `Template '${templateName}' not found (HTTP ${templateRes.status})`,
          );
        }

        const versionsRes = await coderApi(
          url,
          `/api/v2/templates/${templateRes.data.id}/versions`,
          token,
        );

        const versions = (versionsRes.data || []).map(
          (v: any) => ({
            id: v.id,
            name: v.name,
            createdAt: v.created_at,
            createdBy: v.created_by?.username,
            status: v.job?.status || "unknown",
          }),
        );

        const history = {
          templateName,
          versions,
          checkedAt: new Date().toISOString(),
        };

        const handle = await context.writeResource(
          "versions",
          "history",
          history,
        );
        return { dataHandles: [handle] };
      },
    },
  },
};

async function findCoderBin(): Promise<string> {
  // Try repo-local first
  const repoLocal = `${Deno.cwd()}/.local/bin/coder`;
  try {
    await Deno.stat(repoLocal);
    return repoLocal;
  } catch {
    // Fall back to PATH
    return "coder";
  }
}
