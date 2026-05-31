// ABOUTME: Workflow-scoped report that summarizes burn-in run results.
// ABOUTME: Produces pass/fail assertions for health probe reliability, metrics collection, and event delivery.

export const report = {
  name: "@sandbox/burn-in-summary",
  description:
    "Summarizes burn-in workflow execution results with pass/fail assertions for reliability analysis",
  scope: "workflow" as const,
  labels: ["burn-in", "reliability"],

  execute: async (context: any) => {
    const steps = context.stepExecutions || [];
    const workflowName = context.workflowName;
    const status = context.workflowStatus;

    const succeeded = steps.filter((s: any) => s.status === "succeeded");
    const failed = steps.filter((s: any) => s.status === "failed");
    const skipped = steps.filter((s: any) => s.status === "skipped");

    const assertions: Array<{ name: string; passed: boolean; detail: string }> = [];

    assertions.push({
      name: "workflow-completed",
      passed: status === "succeeded",
      detail: `Workflow ${workflowName} finished with status: ${status}`,
    });

    assertions.push({
      name: "no-step-failures",
      passed: failed.length === 0,
      detail: failed.length === 0
        ? "All steps succeeded"
        : `${failed.length} step(s) failed: ${failed.map((s: any) => `${s.jobName}/${s.stepName}`).join(", ")}`,
    });

    const healthSteps = steps.filter((s: any) => s.modelType === "burn-in/health-probe");
    if (healthSteps.length > 0) {
      const healthSucceeded = healthSteps.every((s: any) => s.status === "succeeded");
      assertions.push({
        name: "health-probe-reliable",
        passed: healthSucceeded,
        detail: healthSucceeded
          ? `All ${healthSteps.length} health probe(s) succeeded`
          : `Health probe failures detected`,
      });
    }

    const metricsSteps = steps.filter((s: any) => s.modelType === "burn-in/metrics-sampler");
    if (metricsSteps.length > 0) {
      const metricsSucceeded = metricsSteps.every((s: any) => s.status === "succeeded");
      assertions.push({
        name: "metrics-scrape-reliable",
        passed: metricsSucceeded,
        detail: metricsSucceeded
          ? `All ${metricsSteps.length} metrics scrape(s) succeeded`
          : `Metrics scrape failures detected`,
      });
    }

    const eventSteps = steps.filter((s: any) => s.modelType === "burn-in/event-log");
    if (eventSteps.length > 0) {
      const eventSucceeded = eventSteps.every((s: any) => s.status === "succeeded");
      assertions.push({
        name: "event-recording-reliable",
        passed: eventSucceeded,
        detail: eventSucceeded
          ? `All ${eventSteps.length} event recording(s) succeeded`
          : `Event recording failures detected`,
      });
    }

    const passCount = assertions.filter((a) => a.passed).length;
    const failCount = assertions.filter((a) => !a.passed).length;
    const allPassed = failCount === 0;

    const verdict = allPassed ? "PASS" : "FAIL";

    const markdown = [
      `# Burn-In Summary: ${workflowName}`,
      "",
      `**Verdict**: ${verdict} (${passCount}/${assertions.length} assertions passed)`,
      `**Workflow status**: ${status}`,
      `**Steps**: ${succeeded.length} succeeded, ${failed.length} failed, ${skipped.length} skipped`,
      "",
      "## Assertions",
      "",
      "| # | Name | Result | Detail |",
      "|---|------|--------|--------|",
      ...assertions.map(
        (a, i) =>
          `| ${i + 1} | ${a.name} | ${a.passed ? "PASS" : "FAIL"} | ${a.detail} |`,
      ),
      "",
    ].join("\n");

    const json = {
      verdict,
      workflowName,
      workflowStatus: status,
      assertions,
      summary: {
        total: assertions.length,
        passed: passCount,
        failed: failCount,
      },
      steps: {
        succeeded: succeeded.length,
        failed: failed.length,
        skipped: skipped.length,
      },
    };

    return { markdown, json };
  },
};
