# Troubleshooting

Symptoms and fixes when an image build or audit fails.

## Symptoms

| Symptom | Resolution |
| --- | --- |
| `no match for platform in manifest` | The base image does not publish that platform; inspect it and drop the platform or change the base. A per-architecture vendor tag can fail like this under `--check` even when `docker pull --platform` succeeds; validate that image with a native build on its target architecture |
| `unsupported platform` from the `case` | Add the platform deliberately across the contract, or remove it from the build command |
| `MSB4024` loading `nuget.g.props`, "Root element is missing" | Local `obj/` files reached the context as empty stubs; re-exclude `**/obj/**` rather than `**/obj` (DF025) |
| `NETSDK1083` naming a semicolon-separated identifier | Quote the RID list as shown in the .NET pattern instead of escaping `;` as `%3B` |
| Container ignores `docker stop` for ten seconds | The entrypoint shell is PID 1; use exec form or `exec` |
| Entrypoint starts `dotnet .dll` | A stage reads a build argument it declared without a default; redeclare it with the default |
| Non-root process cannot write a volume | Create the path in the image, owned by the runtime user, before `VOLUME` |
| `/bin/sh: set: Illegal option -` | The Dockerfile has CRLF line endings; renormalise it under the shared `.gitattributes` (`* text=auto eol=lf`) |
| DF018 on prose comments | Reword comments that begin with an uppercase instruction keyword |
