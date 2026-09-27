---
description: 'Model Context Protocol (MCP) server tool conventions — attributes, descriptions and naming.'
applyTo: '**/*.cs'
---

# MCP (Model Context Protocol)

Apply these conventions to MCP tools. Use the [dotnet-mcp skill](../skills/dotnet-mcp/SKILL.md)
for HTTP implementation, SDK-specific behavior and validation. This file owns naming and
description rules; the skill references them rather than repeating them.

## Descriptions

- Use separate `[McpServerTool]` and `[Description(...)]` attributes on exposed methods.
  Describe every model-supplied parameter and every public output DTO property, including nested
  types. SDK/DI-injected parameters are not model arguments.
- Write concise, readable plain English without XML markup or localization. Explain the action
  and domain; distinguish similar tools with explicit cross-references where useful.
- Put units, ranges and constraints on parameters/properties rather than repeating them in the
  method description. For string-valued enums, list every accepted value and its meaning.
  For complex inputs, summarize the key fields and constraints.
- Keep XML documentation for developers separate from model guidance; neither replaces the other.
  Avoid narrating an obvious return type or repeating identical descriptions across tools.

## Naming

- Include the domain noun so tool names are unique across tool classes: `GetOrder`, not `GetItem`.
  Use verb-first actions such as `CancelSubscription`, and `Get<Noun>` / `Get<Noun>s` for single
  and collection queries.
- Prefer short, everyday vocabulary. Check that both the C# name and its exposed `snake_case`
  form remain readable and unambiguous.
- When renaming a tool, update its exposed-name references in configuration (including
  `IncludeTools` / `ExcludeTools`), prompts, instructions, documentation and request examples.
