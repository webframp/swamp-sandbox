FROM node:22-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl jq bash ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install swamp
RUN curl -fsSL https://swamp.club/install.sh | bash

# Install Claude Code CLI
RUN npm install -g @anthropic-ai/claude-code

# Non-root user for workspace
RUN adduser --disabled-password --gecos "" --shell /bin/bash coder

# Seed example models, workflows, extensions, and docs into the workspace
COPY --chown=coder:coder models/ /home/coder/models/
COPY --chown=coder:coder workflows/ /home/coder/workflows/
COPY --chown=coder:coder extensions/ /home/coder/extensions/
COPY --chown=coder:coder examples/ /home/coder/examples/

# Pre-seed Claude Code config to skip interactive first-run dialogs
RUN echo '{"hasCompletedOnboarding":true,"bypassPermissionsModeAccepted":true,"autoUpdaterStatus":"disabled","hasAcknowledgedCostThreshold":true,"projects":{"/home/coder":{"hasTrustDialogAccepted":true,"hasCompletedProjectOnboarding":true}}}' > /home/coder/.claude.json && chown coder:coder /home/coder/.claude.json

USER coder
WORKDIR /home/coder
