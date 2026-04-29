FROM node:22-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl jq bash ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install swamp
RUN curl -fsSL https://swamp.club/install.sh | bash

# Install Claude Code CLI
RUN npm install -g @anthropic-ai/claude-code@2.1.121

# Non-root user for workspace
RUN adduser --disabled-password --gecos "" --shell /bin/bash coder
USER coder
WORKDIR /home/coder
