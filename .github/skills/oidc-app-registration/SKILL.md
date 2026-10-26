---
name: oidc-app-registration
description: 'Create, rotate, audit and troubleshoot OpenID Connect sign-in registrations for self-hosted web applications with Microsoft Entra ID or Google Workspace: redirect URIs, secrets in a secret store, user assignment, claims for authorization, reverse-proxy callbacks, and moving an internal host to a public domain.'
---

# OIDC App Registration

Register a self-hosted web application with an identity provider so people sign in with OpenID
Connect, store its secret safely, and keep the registration aligned with the host as it moves
between private and public domains. Use Microsoft Entra ID or Google Workspace; the application
code, ingress and deployment configuration are the same for both apart from the claims used for
authorization.

## Authorities

- [Workflow instructions](../../instructions/workflow.instructions.md) own credential handling and
  public-repository confidentiality. Registration identifiers, tenant IDs and real hostnames belong
  only in private deployment configuration.
- [Configuration instructions](../../instructions/dotnet.configuration.instructions.md) own where
  settings and secrets live for .NET applications.
- [Blazor frontend](../blazor-frontend/SKILL.md) owns the host-side cookie, antiforgery and
  multi-replica rules for a Blazor application that signs users in this way.

Creating a registration, granting consent and writing a secret change shared identity state. Do them
only when the user has asked for the registration, and report the identifiers you created.

## Workflow

### 1. Establish the Contract

Record before creating anything:

- the exact public origin (scheme, host, port) the browser will use, not the in-cluster address;
- the application's callback paths. ASP.NET Core defaults are `/signin-oidc`,
  `/signout-callback-oidc` and front-channel `/signout-oidc`;
- whether a TLS-terminating proxy sits in front, and how the application learns the original scheme;
- which claim the application authorizes on, and who must be able to sign in;
- the secret store the deployment reads from and its naming convention. Find it from an existing
  secret name, not by reading secret values.

Reuse one registration per application and environment. Never share a client between unrelated
applications, because consent, assignment and secret rotation then couple them.

### 2. Choose the Provider and Authorization Claim

| Concern | Microsoft Entra ID | Google Workspace |
| --- | --- | --- |
| Authority | `https://login.microsoftonline.com/<tenant-id>/v2.0` | `https://accounts.google.com` |
| Stable user claim | `oid` (per tenant, stable across applications) | `sub` (stable, opaque) |
| Readable identity | `preferred_username`, `name` | `email` (needs the `email` scope), `name` |
| Restrict to an organisation | Single-tenant audience plus required user assignment | Internal consent screen, or check the `hd` claim |
| Scriptable registration | Yes, with Azure CLI and Microsoft Graph | No; create web OAuth clients in the Cloud console |

Authorize on an immutable identifier (`oid` or `sub`). An email address can be reassigned. When the
application lets configuration choose the claim, set it to match the provider; Google tokens have no
`oid`. Audit fields should use the same stable identifier.

Guests matter: an Entra guest signs in with an `oid` from the resource tenant, not their home
tenant. A Google client whose users include accounts outside the Workspace domain needs an
**External** consent screen.

### 3. Register With Microsoft Entra ID

Run as a user allowed to create applications and grant admin consent. Replace the placeholders.

```powershell
$name   = 'example-admin'
$origin = 'https://app.example.com'

$appId = az ad app create --display-name $name --sign-in-audience AzureADMyOrg `
    --web-redirect-uris "$origin/signin-oidc" "$origin/signout-callback-oidc" --query appId -o tsv
$spId  = az ad sp create --id $appId --query id -o tsv
$objId = az ad app show --id $appId --query id -o tsv
```

`az ad app update --set web.logoutUrl=...` fails because the CLI cannot address the nested `web`
object. Patch through Microsoft Graph instead, writing the body to a file:

```powershell
$body = Join-Path $env:TEMP 'graph-body.json'
@{ web = @{ logoutUrl = "$origin/signout-oidc"
            redirectUris = @("$origin/signin-oidc", "$origin/signout-callback-oidc") } } |
    ConvertTo-Json -Depth 3 | Set-Content $body
az rest --method PATCH --uri "https://graph.microsoft.com/v1.0/applications/$objId" `
    --headers 'Content-Type=application/json' --body "@$body"
```

Restrict sign-in to assigned people, then assign each one with the default role:

```powershell
'{"appRoleAssignmentRequired":true}' | Set-Content $body
az rest --method PATCH --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$spId" `
    --headers 'Content-Type=application/json' --body "@$body"

$userId = az ad user show --id 'person@example.com' --query id -o tsv
@{ principalId = $userId; resourceId = $spId; appRoleId = '00000000-0000-0000-0000-000000000000' } |
    ConvertTo-Json | Set-Content $body
az rest --method POST --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$spId/appRoleAssignedTo" `
    --headers 'Content-Type=application/json' --body "@$body"
Remove-Item $body
```

Add the delegated `openid` and `profile` permissions and grant admin consent, so guests and users
without consent rights are not stopped at a consent prompt:

```powershell
az ad app permission add --id $appId --api 00000003-0000-0000-c000-000000000000 `
    --api-permissions 37f7f235-527c-4136-accd-4a02d197296e=Scope 14dad69e-099b-42c9-810b-d002981feec1=Scope
az ad app permission admin-consent --id $appId
```

Use the authorization code flow with PKCE. Leave implicit ID-token issuance disabled.

### 4. Register With Google Workspace

Google web OAuth clients cannot be created from the CLI. In the Google Cloud console, under
**APIs & Services**:

1. Configure the **OAuth consent screen**. Choose **Internal** to limit sign-in to the Workspace
   organisation, or **External** when accounts outside it must sign in. Publish an External app;
   unpublished External apps only admit listed test users and issue short-lived refresh tokens.
2. Request only `openid`, `email` and `profile`. These are non-sensitive scopes and need no
   verification.
3. Create an **OAuth client ID** of type **Web application** with the exact redirect URIs, such as
   `https://app.example.com/signin-oidc`. Google matches them exactly, including the trailing path.
4. Copy the client ID and secret once, straight into the secret store (step 5).

Google offers no per-application user assignment comparable to Entra's. With an External screen,
any Google account can complete sign-in, so the application must authorize every request against
its own allowlist of `sub` values, or check `hd` and `email_verified`.

### 5. Store the Secret Without Exposing It

Never print a client secret, pass it as a command-line argument or commit it. Write it to a
temporary file, load it into the secret store with an expiry, and delete the file:

```powershell
$secretName = '<prefix>--Section--ClientSecret'
$tmp = Join-Path $env:TEMP ([IO.Path]::GetRandomFileName())
try {
    $credential = az ad app credential reset --id $appId --display-name "$name-store" --years 1 --append `
        --query '{password:password}' -o json | ConvertFrom-Json
    [IO.File]::WriteAllText($tmp, $credential.password)
    $expires = (Get-Date).ToUniversalTime().AddYears(1).AddDays(-1).ToString('yyyy-MM-ddTHH:mm:ssZ')
    az keyvault secret set --vault-name '<vault>' --name $secretName --file $tmp --encoding utf-8 `
        --expires $expires --content-type "OIDC client secret: $name" --query name -o tsv
}
finally {
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    Remove-Variable credential -ErrorAction SilentlyContinue
}
```

For Google, paste the secret into the same `--file` flow instead of the credential reset. Match the
secret name to the deployment's configuration-key mapping. Set the store's expiry no later than the
credential's, so expiry alerting fires before sign-in breaks.

Put non-secret settings (authority, client ID, authorized user identifiers) in the private
deployment configuration, not the public application repository.

### 6. Prepare the Reverse Proxy and Host

- When TLS terminates at an ingress, the application must use the forwarded scheme or it builds
  `http://` callbacks that the provider rejects. For ASP.NET Core set
  `ASPNETCORE_FORWARDEDHEADERS_ENABLED=true`, or configure `ForwardedHeadersOptions` with known
  proxies when the network is not trusted.
- Sign-in responses carry correlation, nonce and session cookies. Raise ingress proxy buffer sizes
  (for example `16k`) when the controller's defaults are small.
- Basic Auth at the ingress may stay in front of a private host as defence in depth. Browsers resend
  cached credentials on the provider's form-post callback to the same origin.
- If the host only reads mounted configuration at startup, roll the pods after changing it.

### 7. Verify Before Exposing the Deployment

Start the exact image with the new configuration and a dummy secret, then request the sign-in route
with the proxy's forwarded headers. Check the `Location` header for the correct `client_id`, the
`https` `redirect_uri`, `response_type=code` and `code_challenge_method=S256`. A misconfigured
secret or authority can stop the host from starting, so validate before rolling out with a
`Recreate` strategy or a single replica.

After deployment, confirm the live pods report sign-in as required, and complete one interactive
sign-in with an assigned and an unassigned account.

### 8. Rotate and Remove

- Add a new credential with `--append`, update the secret store, roll the pods, then delete the old
  credential with `az ad app credential delete`. For Google, add a second secret in the console
  before disabling the first.
- When an application is retired, delete its registration or OAuth client and its secret.

## Moving a Private Host to a Public Domain

A private name such as a `.home.arpa` host with a private certificate authority limits who can
reach the sign-in page. Moving to a public domain removes that barrier, so change the deployment
deliberately:

1. Add the new public redirect URIs alongside the old ones. Remove the old URIs only after the move.
2. Issue a certificate from a public CA for the new host; browsers outside the private trust store
   reject the private CA.
3. Keep authorization strict: Entra required user assignment, or Google Internal consent or an
   application allowlist. Being reachable must not mean being able to sign in.
4. Decide whether to keep Basic Auth. It blocks unauthenticated scanning of the sign-in route but
   breaks non-browser clients and complicates sign-out.
5. Rate-limit the sign-in and callback routes at the ingress, and alert on repeated failures.
6. For Entra, consider Conditional Access (MFA, compliant devices) for the registration. For Google,
   enforce 2-Step Verification for the organisation.
7. Re-verify the full sign-in, sign-out and callback flow on the public host before announcing it.

## Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| `AADSTS50011` redirect URI mismatch | The application built an `http://` or internal-host callback; enable forwarded headers or fix the registered URI |
| `AADSTS50105` user not assigned | Required assignment is on and the user lacks an app role assignment |
| Consent prompt for every guest | Admin consent was not granted for the delegated scopes |
| Google `redirect_uri_mismatch` | The URI differs by scheme, host, port or path from the authorized list |
| Google `access_denied` for an outside account | The consent screen is Internal, or External but unpublished without the user as a tester |
| 400 or 502 from the ingress on the callback | Proxy buffers too small for the sign-in cookies |
| Sign-in loop after success | The session cookie is `Secure` but the request reached the application as HTTP without forwarded headers |

## Maintaining This Skill

- Entra and Google registration workflows, assignment, consent and supported authorization claims.
- Secret rotation, redirect URI matching and reverse-proxy callback requirements.
