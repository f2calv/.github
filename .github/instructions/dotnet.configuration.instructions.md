---
description: 'Application configuration layering, options synchronisation, command-line precedence and secret-safety conventions.'
applyTo: '**/appsettings*.json,**/*Config.cs,**/*Options.cs'
---

# Configuration

## Environment Layering

- Use this standard provider order: `appsettings.json`, `appsettings.{Environment}.json`, optional
  `appsettings.Local.json`, optional `appsettings.Local.{Environment}.json`, user secrets,
  environment variables, then any application-specific deployment secret store. Later providers override
  earlier values by key.
- `appsettings.json` is **both** the base configuration and the `Production` environment. Never create an `appsettings.Production.json`.
- An environment-specific file only restates the keys it changes; every other key falls through to the base file.
- Local files are an optional gitignored tier for repositories that need machine-specific or private
  configuration. Do not require them in a repository that deliberately stores its complete
  environment configuration in tracked private files.
- `appsettings.Local.json` overrides the base and every environment.
  `appsettings.Local.{Environment}.json` contains only environment-specific local overrides.
- Use the standard double-underscore form for nested environment variables, for example `Prefix__SectionName__PropertyName`, so orchestrators and CI can override any value at runtime.
- Prefer user secrets for developer credentials. A repository may use gitignored local files for
  private configuration when its repository-specific instructions define that tier.
- Add a deployment secret store only after enough preceding configuration has been loaded to resolve
  its endpoint and authentication settings. Rebind affected options after adding it.

## Options Synchronisation

- Define every configuration property with a sensible default on the options record or class, so the application runs out of the box and each value remains overridable.
- Treat options-type defaults as the canonical base configuration. Do not repeat a key in
  `appsettings.json` when its value is identical to the code default; the duplicate adds noise and
  can drift. Keep base-file keys only for required values without a safe code default, deliberate
  overrides, placeholders that make a tracked example runnable, or collection content that cannot
  be expressed as an empty/default object.
- When adding, renaming or removing a bindable property on an options type — or on any nested type reachable from it — review the base file, each applicable tracked environment override, each existing local tier used by the repository, and every documentation example in the same change. Add or retain a key only where that provider intentionally differs from the code default.
- Add a key to an environment-specific file only when that environment genuinely needs to override the type's default.
- Add a key to a local file only when it differs from the tracked defaults or contains private
  configuration that cannot be committed to a public repository.
- Apply data-annotation validation to required values, and preserve existing validation when changing an options model.

## Secret Safety

- In a public repository, tracked configuration files must never contain real secrets or personally
  identifiable information. Use safe public defaults, generic placeholders or `null`.
- Gitignored local files may contain private values needed for development or deployment, but remain
  credentials borrowed from their source: never print them, persist them to logs or copy them into a
  public repository.
- Never commit credentials, access or refresh tokens, secret-bearing connection strings, API keys or
  passwords in any repository. In a public repository, also never commit real account identifiers,
  hostnames, IP addresses, phone numbers or tenant identifiers.
- A private deployment repository may track non-secret environment configuration and identifiers
  when it owns that desired state. Keep credentials in its deployment secret store rather than in a
  ConfigMap.
- Supply continuous integration credentials through repository secrets and environment variables.
- Treat every file shipped in a published package, container image or sample output as public.
- Keep credential caches, token files and account state outside the repository. Never add their contents or paths to tracked examples, logs, tests or documentation.
- Never log or echo a secret, an `Authorization` header, or any encoded form derived from one, including in progress output, error messages and exception detail.
- Keep tracked examples runnable once the consumer supplies their own credentials.

## Command-Line Precedence

- Where a tool exposes command-line options, a command-line value always overrides a configuration value.
- Every credential or connection value accepted on the command line must also be bindable from configuration, so the tool can run unattended without the value appearing in a process command line.
