---
description: 'Application configuration layering, options synchronisation and secret-safety conventions.'
applyTo: '**/appsettings*.json'
---

# Configuration

## Environment Layering

- Load `appsettings.json` first, then `appsettings.{Environment}.json`, then any optional local override file, then user secrets, then environment variables, then the deployment secret store. Later providers override earlier values by key.
- `appsettings.json` is **both** the base configuration and the `Production` environment. Never create an `appsettings.Production.json`.
- An environment-specific file only restates the keys it changes; every other key falls through to the base file.
- Use the standard double-underscore form for nested environment variables, for example `Prefix__SectionName__PropertyName`, so orchestrators and CI can override any value at runtime.
- Store local development and test credentials in user secrets, never in a tracked file.

## Options Synchronisation

- Define every configuration property with a sensible default on the options record or class, so the application runs out of the box and each value remains overridable.
- When adding, renaming or removing a bindable property on an options type — or on any nested type reachable from it — update every applicable `appsettings*.json` file and every documentation example in the same change.
- Add a key to an environment-specific file only when that environment genuinely needs to override the type's default.
- Apply data-annotation validation to required values, and preserve existing validation when changing an options model.

## Secret Safety

- Tracked configuration files must never contain real secrets or personally identifiable information. Use safe public defaults, generic placeholders or `null`.
- Never commit credentials, access or refresh tokens, connection strings, API keys, account identifiers, real hostnames, IP addresses, phone numbers or tenant identifiers.
- Supply continuous integration credentials through repository secrets and environment variables.
- Treat every file shipped in a published package, container image or sample output as public.
- Keep credential caches, token files and account state outside the repository. Never add their contents or paths to tracked examples, logs, tests or documentation.
- Never log or echo a secret, an `Authorization` header, or any encoded form derived from one, including in progress output, error messages and exception detail.
- Keep tracked examples runnable once the consumer supplies their own credentials.

## Command-Line Precedence

- Where a tool exposes command-line options, a command-line value always overrides a configuration value.
- Every credential or connection value accepted on the command line must also be bindable from configuration, so the tool can run unattended without the value appearing in a process command line.
