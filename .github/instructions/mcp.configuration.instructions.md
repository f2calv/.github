---
description: 'Model Context Protocol configuration conventions for server scope, credentials, naming, reproducibility and validation.'
applyTo: '**/mcp.json,**/.mcp.json'
---

# MCP Configuration

## Ownership And Scope

- Put services needed across unrelated workspaces in the VS Code user-profile `mcp.json`.
- Put repository-specific capabilities in tracked `.vscode/mcp.json`. Keep the server definition
  portable and free of deployment-environment coordinates so contributors can supply their own
  endpoints and credentials.
- Use workspace `.mcp.json` or user `~/.copilot/mcp-config.json` only when Agent Host portability is
  required. Do not duplicate the same server in both formats.
- Let an extension own servers it contributes dynamically. Do not duplicate an extension-managed
  server in `mcp.json` unless the explicit configuration provides a different capability.
- Keep private cluster endpoints, database numbers and internal service names in a private repository,
  a user-profile configuration or caller-supplied inputs. Never publish them through a public shared
  customization repository.

## Credentials And Inputs

- Never embed credentials, tokens, authorization values or secret-bearing URLs in MCP configuration.
  Use `${input:...}` with `"password": true`, environment variables or a gitignored environment file.
- Use one source of truth per value. Do not prompt separately for variables already supplied by an
  environment file.
- When a server requires credential transformation, invoke a small repository-owned wrapper that
  reads the secret at startup and never writes or logs it.
- Public repositories may include synthetic endpoint examples, but real hosts and identifiers must
  come from inputs without a private default.

## Server Definitions

- Give every server a stable, descriptive name. Use one naming pattern within a related server family
  and include the environment or data scope only when it prevents ambiguity.
- Reuse shared endpoint and credential inputs across related HTTP servers instead of prompting once
  per route.
- Pin local server packages, container images and source checkouts to an immutable version or digest.
  Never use `latest`, an unversioned package invocation or an unpinned Git branch.
- For PowerShell stdio wrappers, use `-NoProfile` and `-NonInteractive`. Resolve workspace scripts via
  `${workspaceFolder}` rather than an absolute path.
- Pass configuration as separate argument-array entries. Do not construct a shell command string or
  route secrets through command-line arguments when an environment variable is supported.

## Validation

- Validate `mcp.json` with the VS Code schema and review the MCP output log after changing a server.
- Start the changed server and verify its tool inventory before considering the configuration done.
- Remove stale or duplicate registrations through **MCP: List Servers**. Enabled state and trust are
  stored separately from `mcp.json`, so deleting a definition does not by itself clear cached state.
