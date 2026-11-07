# WireGuard Workstation Onboarding

Give another workstation the same approved access through an existing UniFi WireGuard server.
This is a Windows-first procedure with portable network and trust requirements. Keep actual
endpoints, allocations, certificate fingerprints and custody locations in private operator records;
all angle-bracket values below are placeholders, not a runnable configuration.

## Separate The Three Requirements

| Requirement | What the workstation needs | What it does not need |
| --- | --- | --- |
| VPN authentication | Its own WireGuard private key, assigned tunnel address and server peer configuration | Another client's profile or any TLS certificate |
| Private name resolution | A reachable internal resolver with records for the private namespace | Public DNS records for `home.arpa` |
| HTTPS trust | The existing public root CA certificate and a server presenting a valid certificate chain | Root/issuing CA private keys, CA passphrase or server leaf private keys |

WireGuard authenticates with public keys, not TLS. A TLS client certificate is needed only if a
particular application explicitly requires mutual TLS; it is not a prerequisite for the tunnel.
Do not create a new CA or reissue service certificates just to add a workstation.

## 1. Collect Inputs And Inspect Before Changing Anything

Obtain the following through approved private records and operator-controlled secure storage:

| Input | Purpose |
| --- | --- |
| Existing UniFi server and public endpoint/UDP port | Select the working server, including its alternate public/DDNS address behind NAT |
| VPN pool and approved destination CIDRs | Allocate a unique address and reproduce the access scope, not a full tunnel |
| Internal resolver IP and private suffixes | Include the resolver's address in the routed destinations |
| Existing HTTPS service FQDN and expected internal address | Use a current low-risk service, not a retired setup canary |
| Public root CA certificate and independently trusted SHA-256 fingerprint | Verify the trust anchor before importing it |
| Target OS, local privileges and application list | Identify DNS policy, certificate stores, WSL/containers and CLI requirements |
| Approved custody location for the new profile | Keep the private key outside repositories and shared download folders |

The public root certificate may be in the operator's encrypted PKI backup, an approved certificate
distribution store or an existing workstation's root store. Export only the public certificate if
using the existing workstation. Never copy a whole PKI backup, retrieve issuing keys from a secret
store or export a PFX containing private keys for routine client onboarding. Confirm the source
with the operator; do not search unrelated personal files for it.

Read the server's current settings and the working client's non-secret route/DNS settings locally.
Never print a WireGuard configuration, use `wg showconf`, capture a QR code or put keys in chat,
logs, Git or screenshots. Compare only endpoint, address family, route scope and DNS policy.

Before writes, capture the target's routes, DNS servers, existing DNS policies and certificate
trust, plus the server's client allocation and access rules. Check destination/VPN pools against
the target's LAN, other VPNs, virtual adapters and container networks. An overlapping local subnet
can divert traffic away from the VPN; stop and design a remedy rather than claiming parity.

Obtain approval for the new peer and endpoint changes, including administrator-level DNS or
machine-wide trust changes. Do not disable a managed workstation's security controls or another
VPN. Record exact rollback values privately.

## 2. Reuse The Existing Server And Edge Path

In UniFi Network, find the existing server under **Settings > VPN > VPN Server**; UI labels vary
by release. Confirm the VPN pool, listener, alternate address, routes/access rules and DNS options.
Do not recreate the server, delete old experiments or change existing clients during onboarding.

When UniFi is behind another router, verify the upstream UDP forwarding reaches its WAN address
and the client endpoint is the public/DDNS address, not that private WAN address. With direct public
WAN, no extra upstream forwarding is needed. CGNAT or a non-routable upstream connection requires
a separately approved reachability design; client settings cannot fix it.

Confirm firewall policy permits this new VPN client to the approved destinations and the internal
resolver on both UDP and TCP 53. Account for rules scoped to individual clients rather than the
entire VPN pool. Do not expose DNS, service HTTPS or management ports publicly as a workaround.

Adding one peer normally needs no router, DNS-record, DHCP or server-certificate change. Back up
the affected controller/router before any separately approved infrastructure change.

## 3. Create A Unique Client And Preserve Split Routing

1. Select **Add Client** on the existing UniFi WireGuard server.
2. Use a unique operator-chosen device label and an unused assigned tunnel address. Retain the
   generated address/prefix unless the server's documented allocation requires otherwise.
3. Download the one-time configuration directly to approved secure storage, then save the client
   as required by the current UI. If export was missed, regenerate only this new client.
4. Inspect the configuration locally. Keep the generated private key, server public key and
   preshared key, if supplied. Never reuse the source workstation's profile or tunnel address.
5. Replace generated `0.0.0.0/0` and `::/0` peer routes with the approved internal CIDRs:

   ```ini
   AllowedIPs = <approved-lan-cidr>, <other-approved-cidr>
   ```

6. Include the resolver and each required service destination, adding a resolver `/32` or `/128`
   route only if it is outside the approved subnet routes. Do not route every VLAN or the VPN pool
   merely because it exists. `AllowedIPs` installs client routes; it does not grant server-side
   firewall permission.
7. Verify the public endpoint and port. Preserve MTU defaults initially. Add
   `PersistentKeepalive = 25` only when NAT/idle reconnect behaviour warrants it.
8. Decide DNS using the next section before activating the profile.

Remove IPv6 default routes for an IPv4-only split tunnel. If internal DNS returns AAAA records,
either provide approved IPv6 tunnel routes/firewall access or correct the internal DNS answer;
do not globally disable workstation IPv6 as a shortcut.

Install WireGuard from its [official distribution](https://www.wireguard.com/install/), then use
**Import tunnel(s) from file** on Windows. Keep the source profile protected until reconnect and
recovery requirements are met; remove transient export/download copies afterward. The imported
configuration is also sensitive.

## 4. Configure Private DNS Deliberately

The internal resolver must answer the actual private service names. `home.arpa` is a private
namespace, not a publicly resolvable zone; VPN transport alone does not create its records.
Use full names such as `service.home.arpa`, rather than relying on a search suffix.

Choose one approved policy:

- **Tunnel DNS:** set `DNS = <internal-resolver-ip>` in the WireGuard interface configuration.
  The internal resolver must also resolve ordinary internet names. Scope this setting to the
  tunnel; do not permanently point the external Wi-Fi/Ethernet adapter at an unreachable home
  resolver. Destination split routing and DNS splitting are different: this may send ordinary
  DNS queries home while their application traffic remains outside the VPN.
- **Namespace-specific Windows DNS:** use the Name Resolution Policy Table (NRPT) to direct only
  approved private suffixes to the internal resolver. This needs an approved elevated workflow.
  Check existing effective/group-policy rules first; do not overwrite them. When retaining the
  external connection's DNS for ordinary names, do not also configure a conflicting tunnel-wide
  DNS policy.

For the NRPT option, inspect with `Get-DnsClientNrptPolicy -Effective` and
`Get-DnsClientNrptRule`. After checking for conflicting rules, the following illustrates one new
locally owned rule; substitute the resolver and keep its generated rule name in private rollback
records:

```powershell
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0
$rule = Add-DnsClientNrptRule -Namespace '.home.arpa' `
    -NameServers '<internal-resolver-ip>' -Comment 'Private VPN DNS' -PassThru
$rule.Name
Clear-DnsClientCache
```

NRPT rules persist when WireGuard disconnects. Private names will intentionally fail off-network
unless the resolver is reachable on the LAN; remove the exact new rule on rollback, or use approved
lifecycle management if connected-only policy is required. Never remove all NRPT rules.

With non-default `AllowedIPs`, WireGuard delegates to
[ordinary Windows routing and multihomed DNS behaviour](https://git.zx2c4.com/wireguard-windows/about/docs/netquirk.md).
The `DNS` field alone is not a guarantee against private DNS leakage. Where no-leak resolution is
required, verify the effective namespace policy and actual resolver path. Browser secure DNS,
application DoH, proxies and independent resolvers may bypass OS policy; configure per-application
exceptions through approved settings and verify them, rather than disabling security globally.

The public WireGuard DDNS endpoint must resolve before the tunnel starts; never place that bootstrap
name under a private-only resolver dependency.

## 5. Install Only Public CA Trust

Retrieve the public root certificate without private material. Verify its SHA-256 certificate
fingerprint against an independent authenticated operator record, and inspect that it is the
intended CA with valid dates and CA basic constraints. A matching subject name is not proof of
identity.

For a file-transfer hash, `Get-FileHash -LiteralPath '<public-root-certificate-path>' -Algorithm SHA256`
must match an independently supplied hash of that exact file. A file hash is not a certificate
fingerprint: PEM and DER encodings of the same certificate have different file hashes.

On Windows, import the single verified public root into the current user's **Trusted Root
Certification Authorities** store through the certificate UI, or with
[Import-Certificate](https://learn.microsoft.com/en-us/powershell/module/pki/import-certificate):

```powershell
Import-Certificate -FilePath '<public-root-certificate-path>' `
    -CertStoreLocation 'Cert:\CurrentUser\Root' -ErrorAction Stop
```

Verify the imported thumbprint and expiry in that store. Use `Cert:\LocalMachine\Root` only when
machine-wide trust is explicitly approved and an elevated workflow performs it. Never import a
server leaf or an intermediate as a trusted root. The server should present the leaf plus the
required intermediate chain; an incomplete chain is a server-side problem.

Restart affected applications if needed. Windows browsers, service accounts, Git/curl TLS backends,
Java, Python, WSL and containers do not necessarily share one trust store. Identify each actual
consumer and use its supported CA mechanism, preserving existing public roots. Linux trust updates
and macOS Keychain imports likewise require their OS-specific workflow and approval. No consumer
needs the CA private key. Do not accept certificate warnings, use `curl -k`, disable Git TLS
verification or change Kubernetes to `insecure-skip-tls-verify`.

Kubernetes kubeconfig commonly embeds its own cluster CA and credentials. Transfer or provision
those separately through the approved access process; importing the HTTPS root neither grants
cluster access nor replaces its CA. Keep an API endpoint that matches the API certificate SANs.

## 6. Validate From A Genuinely External Network

Ask before running connectivity tests. Use an external hotspot or another network outside the
home LAN; testing on home Wi-Fi may prove only direct/hairpin access. Do not copy source-device
success into the new workstation's evidence.

Before activation, confirm the public endpoint resolves and record the external default path.
After activation, require each of these independent outcomes:

| Layer | Required evidence |
| --- | --- |
| Tunnel | Recent handshake and increasing traffic counters in the local WireGuard UI after a request |
| Routes | Internal service and resolver routes use WireGuard; ordinary internet destinations still use the external interface |
| Reachability | Required TCP service ports work through those routes; an ICMP response alone is insufficient |
| Resolver | Direct query to the internal resolver returns the expected internal address |
| Normal DNS path | The same FQDN resolves without selecting a server; browser/CLI resolves it through the approved policy |
| TLS | HTTPS by FQDN validates chain, validity and hostname without bypass flags; expected login/401 response is acceptable |
| Application | Each required browser/CLI/API performs its intended authenticated operation |
| Lifecycle | Deactivate/reactivate, idle reconnect and, if required, reboot pass; off-tunnel ordinary internet/DNS still work |

Useful Windows checks, with operator-supplied values:

```powershell
Get-NetRoute -AddressFamily IPv4
Get-DnsClientServerAddress
Find-NetRoute -RemoteIPAddress '<internal-service-ip>'
Find-NetRoute -RemoteIPAddress '<ordinary-internet-ip>'
Test-NetConnection -ComputerName '<internal-service-ip>' -Port 443
Resolve-DnsName -Name 'service.home.arpa' -Server '<internal-resolver-ip>'
Resolve-DnsName -Name 'service.home.arpa'
curl.exe --head --silent --show-error 'https://service.home.arpa/'
if ($LASTEXITCODE -ne 0) { throw 'HTTPS validation failed; investigate DNS, routing and TLS trust.' }
```

Test the actual required service port, not always 443, and use a supported read-only URL if HEAD is
not supported. A direct `-Server` DNS query proves resolver reachability but not normal DNS policy;
retain both checks. A trusted HTTP response is TLS evidence, not authenticated application evidence.
Keep addresses, counters and application output in private evidence; never capture credentials or
user content. Static skill tests do not prove live VPN connectivity.

## 7. Troubleshoot By Layer And Roll Back Precisely

| Symptom | Check before changing anything |
| --- | --- |
| No handshake | Public/DDNS resolution, endpoint port, upstream UDP forwarding, CGNAT, saved client and its keys |
| Handshake but no service | Split route, subnet overlap, peer-specific firewall permission and service listener |
| Direct DNS works, normal DNS fails | Effective NRPT policy, competing adapters, cached answers and application DoH/proxy |
| Wrong/private-inaccessible AAAA answer | Approved IPv6 routes and internal DNS view |
| Unknown CA | Verified root in the actual application's trust store and server intermediate chain |
| Hostname mismatch or expired leaf | Correct service FQDN/SAN, workstation clock and server certificate renewal |
| Internet fails only with VPN on | Accidental default `AllowedIPs`, Windows kill-switch behaviour or unreachable tunnel DNS |
| Tunnel stalls after idle or larger requests | NAT timeout, keepalive and measured MTU/path behaviour |

For a failed onboarding:

1. Deactivate and remove only the new workstation tunnel.
2. Remove only the new UniFi peer to revoke that device; keep existing peers/server/forwarding.
3. Remove only locally owned DNS rules by their recorded rule names, restore changed adapter DNS
   and clear the DNS cache. For example, use `Remove-DnsClientNrptRule -Name '<new-rule-name>' -Force`.
4. Remove the root by verified thumbprint from the exact store only if this onboarding introduced
   it and rollback requires withdrawing trust. Never remove pre-existing shared trust or all roots.
5. Remove transient secret-bearing exports and confirm ordinary internet, DNS and existing clients.

VPN revocation, CA trust removal and application credential revocation are separate controls.
For a lost workstation, revoke its WireGuard peer and relevant application credentials; deleting
the local profile or certificate is not remote revocation.

Report peer creation, split-route/DNS policy, trust-store scope, external validation, reconnect,
cleanup and unresolved gaps. State clearly when this was documentation-only and no live client
was provisioned.
