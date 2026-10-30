# example-message

A synthetic Helm chart demonstrating a typed, conditional ConfigMap. It is a local validation
fixture, not a published application chart, and has no dependencies or running workload.

## Local Usage

From this chart directory, with approval for local validation:

```console
helm lint . --strict
helm template example . --namespace example
helm template example . --namespace example --values ci/custom-values.yaml
helm template example . --namespace example --values ci/disabled-values.yaml
```

Defaults produce exactly one `v1/ConfigMap` named `example-message` in namespace `example`.
Its `data.message` contains `Hello from the Helm example`. Changing the release name changes
the ConfigMap name; keep the release identity stable during real migrations.
The disabled fixture produces no resources. The custom fixture preserves quotes and template-like
text literally; values are never passed to `tpl`.

## Configuration

Complete defaults:

```yaml
message:
  enabled: true
  text: Hello from the Helm example
```

| Value | Contract |
| --- | --- |
| `message.enabled` | Boolean, default `true`; explicit `false` suppresses the ConfigMap |
| `message.text` | Non-secret string of 1-256 characters |
| `global` | Optional Helm global object; accepted but not consumed by this chart |

The fully owned root and message object reject unknown keys. A reusable umbrella with aliases
or extension keys may need an open root instead; do not transplant this closed schema blindly.
Settings are validated even when the resource is disabled, so an invalid latent value still fails.
This chart has no credentials, persistence, image, Service or ingress contract.

## Invalid Inputs and Packaging

The three files under `tests/invalid/` are expected to fail `helm lint` and `helm template`:
empty text, a string in place of the boolean, and a misspelled message key. Keep them out of `ci/`,
where chart-testing treats values files as successful installation cases.

```console
helm template example . --values tests/invalid/empty-text.yaml
helm package . --destination <temporary-output-directory>
```

The first command must exit nonzero with a schema error naming `message.text`. The second produces
`example-message-0.1.0.tgz`; inspect it for metadata, schema, defaults, template and this README,
and confirm that neither `ci/` nor `tests/` is present.

No dependency update, registry login, publication or cluster access is needed for these checks.
Installing the generated package into a cluster is a separate authorized operation, not part of
local rendering. Successful rendering does not prove Kubernetes admission or runtime behavior.
