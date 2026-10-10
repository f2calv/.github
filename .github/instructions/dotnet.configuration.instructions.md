---
description: 'Application configuration layering, options types and validation, options synchronisation, command-line precedence and secret-safety conventions.'
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

- Give every optional configuration property an explicit safe default on the options record or
  class, so the application runs out of the box and each value remains overridable. Keep required
  credentials and identifiers required rather than supplying plausible-looking fallback values.
- Treat options-type defaults as the canonical base configuration. Do not repeat a key in
  `appsettings.json` when its value is identical to the code default; the duplicate adds noise and
  can drift. Keep base-file keys only for required values without a safe code default, deliberate
  overrides, placeholders that make a tracked example runnable, or collection content that cannot
  be expressed as an empty/default object.
- When adding, renaming or removing a bindable property on an options type — or on any nested type reachable from it — review the base file, each applicable tracked environment override, each existing local tier used by the repository, and every documentation example in the same change. Add or retain a key only where that provider intentionally differs from the code default.
- Add a key to an environment-specific file only when that environment genuinely needs to override the type's default.
- Add a key to a local file only when it differs from the tracked defaults or contains private
  configuration that cannot be committed to a public repository.

## Kubernetes Reload Semantics

- Treat deployment configuration as an immutable startup snapshot in Kubernetes workloads. Bind
  with `IOptions<T>` and roll pods when ConfigMaps, Secrets, environment variables, endpoints or
  infrastructure settings change; this keeps validation, caches and dependent resources coherent.
- Use `IOptionsMonitor<T>` only when the application deliberately supports in-process reload and
  every dependent resource is updated atomically. A mounted ConfigMap changing on disk is not by
  itself a reason to use monitor semantics.
- Keep mutable runtime data such as tenant definitions, user preferences, workflow state and
  versioned policy outside the deployment configuration pipeline. Put it behind a dedicated store
  interface with explicit validation, versioning, cache invalidation and authorization.

## Options Types

- **Validation attributes**: bindable properties carry `System.ComponentModel.DataAnnotations`
  attributes — `[Url]` on URIs, `[Range(1, 65535)]` on ports, `[MinLength(1)]` on secrets and
  identifiers, `[Range(1, int.MaxValue)]` on millisecond timings, `[Range(0.0, 1.0)]` on ratios,
  `[Phone]` on phone numbers. Nested complex objects carry `[ValidateObjectMembers]`. Preserve
  existing validation when changing an options model.
- **Attribute layout**: inline same-family attributes (`[Required, Range(1, 65535)]`); keep different
  families on separate lines (`[Required, Url]` above `[JsonPropertyName]`).
- **Boolean naming**: describe state with a `{Feature}{State}` form (`DistributedLockingEnabled`),
  never an imperative prefix (`EnableDistributedLocking`).
- **Constants extraction**: move `const` keys, profile names and identifiers that are not bindable
  properties into a dedicated `static class` in the same namespace (for example `CacheProfiles` beside
  `CacheConfig`), keeping the options type focused on its bindable shape.
- **Duration properties** (conventionally `Ms`-suffixed) on a configuration root link every consuming
  service in XML documentation: `/// Used by <see cref="MyCompany.Services.WidgetMonitorBgService"/>.`

## Secret Safety

The shared credential and confidentiality rules apply in full. Configuration-specific additions:

- Tracked configuration in a public repository holds only safe public defaults, generic placeholders
  or `null` — never secrets, personal data, real account or tenant identifiers, hostnames or
  addresses.
- Gitignored local files may hold private development or deployment values; never print them, log
  them or copy them into a public repository.
- A private deployment repository may track non-secret environment configuration and identifiers it
  owns. Keep credentials in its deployment secret store, not a ConfigMap.
- Supply CI credentials through repository secrets and environment variables.
- Treat every file shipped in a package, container image or sample output as public.
- Keep credential caches, token files and account state outside the repository and out of tracked
  examples, logs, tests and documentation.
- Keep tracked examples runnable once the consumer supplies their own credentials.

## Command-Line Precedence

- Where a tool exposes command-line options, a command-line value always overrides a configuration value.
- Every credential or connection value accepted on the command line must also be bindable from configuration, so the tool can run unattended without the value appearing in a process command line.
