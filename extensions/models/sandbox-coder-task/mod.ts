/**
 * Dispatches and observes Coder tasks via the CLI and REST API.
 *
 * @module
 */
import { z } from "npm:zod@4";

const GlobalArgsSchema = z.object({
  url: z.string().url().default("http://localhost:3000"),
  templateName: z.string().default("sandbox"),
  presetName: z.string().default("swamp-sandbox"),
});

const TaskStateSchema = z.object({
  id: z.string().optional(),
  prompt: z.string(),
  workspaceName: z.string().optional(),
  status: z.enum(["dispatched", "running", "completed", "failed", "unknown"]),
  dispatchedAt: z.string(),
});

const TaskListSchema = z.object({
  tasks: z.array(
    z.object({
      id: z.string().optional(),
      prompt: z.string().optional(),
      workspaceName: z.string().optional(),
      status: z.string().optional(),
      createdAt: z.string().optional(),
    }),
  ),
  count: z.number().int().nonnegative(),
  checkedAt: z.string(),
});

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
  type: "sandbox/coder-task",
  version: "2026.05.24.1",
  description:
    "Dispatches and observes Coder tasks. Dispatch prompts to Claude Code running inside sandbox workspaces and track execution state as typed data.",
  globalArguments: GlobalArgsSchema,
  resources: {
    state: {
      description: "State of the most recently dispatched task",
      schema: TaskStateSchema,
      lifetime: "infinite" as const,
      garbageCollection: 20,
    },
    list: {
      description: "Current list of tasks",
      schema: TaskListSchema,
      lifetime: "infinite" as const,
      garbageCollection: 5,
    },
  },
  methods: {
    dispatch: {
      description:
        "Dispatch a new task to Claude Code inside the sandbox workspace",
      arguments: z.object({
        prompt: z.string().describe("The task prompt for Claude Code"),
      }),
      execute: async (args: Record<string, unknown>, context: any) => {
        const { templateName, presetName } = context.globalArgs;
        const typedArgs = args as { prompt: string };

        context.logger.info("Dispatching task to template {template}", {
          template: templateName,
        });

        const coderBin = await findCoderBin();
        const cliArgs = [
          "tasks",
          "create",
          "--template",
          templateName,
          "--preset",
          presetName,
          typedArgs.prompt,
        ];

        const result = await runCommand(coderBin, cliArgs);

        if (!result.success) {
          throw new Error(`Task dispatch failed: ${result.stderr}`);
        }

        const state = {
          prompt: typedArgs.prompt,
          workspaceName: parseWorkspaceName(result.stdout),
          status: "dispatched" as const,
          dispatchedAt: new Date().toISOString(),
        };

        const handle = await context.writeResource("state", "last", state);
        return { dataHandles: [handle] };
      },
    },
    list: {
      description: "List current tasks and their status",
      arguments: z.object({}),
      execute: async (_args: Record<string, unknown>, context: any) => {
        context.logger.info("Listing tasks");

        const coderBin = await findCoderBin();
        const result = await runCommand(coderBin, [
          "tasks",
          "list",
          "--output",
          "json",
        ]);

        let tasks: Array<{
          id?: string;
          prompt?: string;
          workspaceName?: string;
          status?: string;
          createdAt?: string;
        }> = [];

        if (result.success && result.stdout) {
          try {
            const parsed = JSON.parse(result.stdout);
            tasks = (Array.isArray(parsed) ? parsed : []).map((t: any) => ({
              id: t.id,
              prompt: t.prompt?.substring(0, 200),
              workspaceName: t.workspace_name || t.workspaceName,
              status: t.status,
              createdAt: t.created_at,
            }));
          } catch {
            // CLI output may not be JSON in all versions
          }
        }

        const taskList = {
          tasks,
          count: tasks.length,
          checkedAt: new Date().toISOString(),
        };

        const handle = await context.writeResource("list", "current", taskList);
        return { dataHandles: [handle] };
      },
    },
    logs: {
      description: "Retrieve logs from a running or completed task",
      arguments: z.object({
        workspaceName: z
          .string()
          .optional()
          .describe("Workspace name to get logs from (uses latest task if omitted)"),
      }),
      execute: async (args: Record<string, unknown>, context: any) => {
        const typedArgs = args as { workspaceName?: string };

        let workspace = typedArgs.workspaceName;

        // If no workspace specified, read the latest dispatched task
        if (!workspace) {
          const lastTask = await context.readResource?.("last");
          workspace = lastTask?.workspaceName;
        }

        if (!workspace) {
          throw new Error(
            "No workspace specified and no previous task found. Dispatch a task first or provide workspaceName.",
          );
        }

        context.logger.info("Fetching logs for workspace {workspace}", { workspace });

        const coderBin = await findCoderBin();
        const result = await runCommand(coderBin, [
          "tasks",
          "logs",
          workspace,
        ]);

        // Return the task state with whatever info we have
        const state = {
          prompt: `[logs for ${workspace}]`,
          workspaceName: workspace,
          status: result.success ? ("completed" as const) : ("unknown" as const),
          dispatchedAt: new Date().toISOString(),
        };

        const handle = await context.writeResource("state", "last", state);
        return { dataHandles: [handle] };
      },
    },
  },
};

function parseWorkspaceName(output: string): string | undefined {
  // Coder CLI typically outputs the workspace name in its creation message
  const match = output.match(
    /workspace\s+["']?([a-zA-Z0-9_-]+)["']?/i,
  );
  return match?.[1];
}
