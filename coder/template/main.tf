terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    docker = {
      source = "kreuzwerker/docker"
    }
  }
}

variable "docker_socket" {
  default     = ""
  description = "(Optional) Docker socket URI"
  type        = string
}

variable "preset_anthropic_api_key" {
  default     = ""
  description = "Anthropic API key baked into the task preset"
  type        = string
  sensitive   = true
}

variable "preset_aws_bearer_token_bedrock" {
  default     = ""
  description = "AWS Bedrock bearer token baked into the task preset"
  type        = string
  sensitive   = true
}

variable "preset_claude_code_use_bedrock" {
  default     = ""
  description = "Bedrock mode flag baked into the task preset"
  type        = string
}

variable "preset_aws_region" {
  default     = "us-east-1"
  description = "AWS region baked into the task preset"
  type        = string
}

variable "preset_claude_provider" {
  default     = "anthropic"
  description = "Claude provider baked into the task preset"
  type        = string
}

provider "docker" {
  host = var.docker_socket != "" ? var.docker_socket : null
}

data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}
data "coder_task" "me" {}

data "coder_parameter" "claude_provider" {
  name         = "claude_provider"
  display_name = "Claude Provider"
  description  = "How Claude Code authenticates: 'anthropic' (API key) or 'bedrock' (AWS)"
  type         = "string"
  default      = "anthropic"
  mutable      = true
}

data "coder_parameter" "anthropic_api_key" {
  name         = "anthropic_api_key"
  display_name = "Anthropic API Key"
  description  = "Your Anthropic API key (required when provider is 'anthropic')"
  type         = "string"
  default      = ""
  mutable      = true
}

data "coder_parameter" "aws_bearer_token_bedrock" {
  name         = "aws_bearer_token_bedrock"
  display_name = "AWS Bearer Token (Bedrock)"
  description  = "AWS bearer token for Bedrock access (required when provider is 'bedrock')"
  type         = "string"
  default      = ""
  mutable      = true
}

data "coder_parameter" "claude_code_use_bedrock" {
  name         = "claude_code_use_bedrock"
  display_name = "Bedrock Mode"
  description  = "Set to '1' to enable Bedrock mode (required when provider is 'bedrock')"
  type         = "string"
  default      = ""
  mutable      = true
}

data "coder_parameter" "aws_region" {
  name         = "aws_region"
  display_name = "AWS Region"
  description  = "AWS region for Bedrock (required when provider is 'bedrock')"
  type         = "string"
  default      = "us-east-1"
  mutable      = true
}

data "coder_workspace_preset" "swamp_sandbox" {
  name    = "swamp-sandbox"
  default = true
  parameters = {
    (data.coder_parameter.claude_provider.name)         = var.preset_claude_provider
    (data.coder_parameter.anthropic_api_key.name)       = var.preset_anthropic_api_key
    (data.coder_parameter.aws_bearer_token_bedrock.name) = var.preset_aws_bearer_token_bedrock
    (data.coder_parameter.claude_code_use_bedrock.name) = var.preset_claude_code_use_bedrock
    (data.coder_parameter.aws_region.name)              = var.preset_aws_region
  }
  prebuilds {
    instances = 0
  }
}

resource "coder_agent" "main" {
  arch = data.coder_provisioner.me.arch
  os   = "linux"

  startup_script = <<-EOT
    set -e
    if [ ! -f "$HOME/.swamp.yaml" ]; then
      swamp init --tool claude
    fi
    swamp --version
    claude --version
  EOT

  display_apps {
    vscode       = false
    web_terminal = true
  }

  metadata {
    display_name = "CPU Usage"
    key          = "cpu"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "RAM Usage"
    key          = "ram"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
  }
}

data "coder_parameter" "ai_prompt" {
  name         = "AI Prompt"
  display_name = "AI Prompt"
  description  = "Prompt for the AI task"
  type         = "string"
  default      = ""
  mutable      = true
}

resource "coder_app" "claude_code" {
  agent_id     = coder_agent.main.id
  slug         = "claude-code"
  display_name = "Claude Code"
  icon         = "/icon/claude.svg"
  command      = "claude --dangerously-skip-permissions \"${data.coder_task.me.prompt}\""
}

resource "coder_ai_task" "task" {
  count  = data.coder_workspace.me.start_count
  app_id = coder_app.claude_code.id
}

resource "docker_image" "workspace" {
  name         = "swamp-sandbox:latest"
  keep_locally = true
  build {
    context = "."
  }
}

resource "docker_container" "workspace" {
  count    = data.coder_workspace.me.start_count
  image    = docker_image.workspace.image_id
  name     = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  hostname = data.coder_workspace.me.name

  entrypoint = ["sh", "-c", replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")]

  env = [
    "CODER_AGENT_TOKEN=${coder_agent.main.token}",
    "ANTHROPIC_API_KEY=${data.coder_parameter.anthropic_api_key.value}",
    "AWS_BEARER_TOKEN_BEDROCK=${data.coder_parameter.aws_bearer_token_bedrock.value}",
    "CLAUDE_CODE_USE_BEDROCK=${data.coder_parameter.claude_code_use_bedrock.value}",
    "AWS_REGION=${data.coder_parameter.aws_region.value}",
  ]

  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }

  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
}
