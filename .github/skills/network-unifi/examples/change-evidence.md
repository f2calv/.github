# Network Change Evidence Example

This synthetic record shows how to assess a secondary storage interface while preserving management
access. All measurements below are invented teaching data, not results from a real network.
Store actual addresses, VLANs, MACs, ports, device names and captures in the owning private record.
No network query, change or benchmark is authorized by this example.

## Before the Change

Record the current state and proposed state separately:

| Layer | Baseline evidence | Proposed change | Must remain unchanged |
| --- | --- | --- | --- |
| UniFi network | Existing management network; overlap inventory includes VPN pools | One distinct storage subnet and DHCP scope | Management subnet, gateway and reservations |
| Switch | Client Connection field plus connected-client confirmation identify the direct port | Change that endpoint port's native network | Uplinks, management port and unrelated clients |
| Host | Interface-to-hardware mapping, current address, global default route and DNS | Secondary profile, no default route or DHCP DNS; source-specific routing | Management profile and control-plane address |
| Service | Current listener/allowlist and approved client paths | Add the intended storage endpoint | Working management fallback and existing auth policy |

The proposal needs an assigned operator, explicit network/port/profile approval, a maintenance
window, and a recovery path not dependent on the interface being changed. Capture the exact prior
port network/link setting, reservation and host profile before mutation. A screenshot of a learned
MAC on an uplink is not proof that the correct endpoint port was identified.

## Worked Observation Sequence

| Stage | Controller view | Endpoint/path evidence | Decision |
| --- | --- | --- | --- |
| Baseline | Management client attached | Global default through management; service reachable from wired and Wi-Fi clients | Establish comparison conditions |
| Port changed | Storage network selected | Carrier up, but no expected DHCP lease | Stop; controller state and carrier do not prove connectivity |
| Lease corrected | Reservation matches current live client record | Correct address; expected negotiated speed | Continue only after management/DNS remain unchanged |
| First routed check | Controller reports healthy | Source-specific route to management-side client exits management, not storage | Reject candidate configuration: reply path is asymmetric |
| Policy corrected | No additional controller change | Source-specific route exits storage gateway/interface | Re-test both directions and every client path |
| Final application check | All intended controller settings present | Wired path passes; Wi-Fi client still fails the application VIP | **Not accepted**, even if throughput improves |

Do not keep changing switch settings once evidence locates the fault in endpoint routing or
client-specific L2 behavior. Follow the [storage-network reference](../references/storage-network.md)
for the exact layer-specific checks. A source policy route is not a second global default route.

## Comparable Measurements

Example conditions: one faster approved peer, source-bound tests, same direction and duration,
three repetitions per stage, 30 seconds per network run, no unrelated workload changes.
Use separate server ports for simultaneous clients. The values here are illustrative medians:

| Path | Network throughput (Gbit/s) | File workload (MiB/s) | Interpretation |
| --- | --- | --- | --- |
| Management baseline | 0.92 | 100 | Original end-to-end path |
| Temporary direct-L2 secondary path | 2.20 | Not measured | Adapter/switch capacity only; not the permanent routed design |
| Routed secondary path before source policy | 0.91 | 98 | Investigate actual reply interface before blaming storage |
| Routed secondary path after source policy | 2.10 | 220 | Candidate improvement; client correctness still blocks acceptance |

For real measurements record direction, source binding, peer capacity, concurrent peers, file size,
cache/warmup state, protocol, disk limits, error counts and variability. Do not compare Gbit/s with
MiB/s as identical units, use one 1 GbE peer to prove a faster uplink, or call an unmeasured file
workload successful. Faster `iperf3` alone does not prove storage/application correctness.

## Acceptance and Rollback

Before any apply, agree thresholds such as:

* management session and global default route remain stable throughout the change;
* all approved wired/Wi-Fi/application paths pass, with no new loss or link-reset events during
  the agreed observation window;
* the routed network median meets the agreed target under the recorded conditions;
* the real authenticated file protocol passes approved create/read/delete checks using only
  uniquely named temporary files;
* the configuration-management second run reports no further intended changes.

The worked sequence above fails the all-client-path gate. Do not report it as completed because
the throughput gate passed. Roll back before further diagnosis if the agreed stop threshold is met.
Deactivate the secondary profile, restore the captured direct-port network/link settings, and
remove new reservations/networks only after their clients are gone. Verify management and all
original client paths after restoration.

The management endpoint is a **manual fallback**, not automatic failover. Automatic failover requires
an independently implemented and tested mechanism.

## Handoff and Cleanup

A truthful report for this scenario is: "Candidate throughput improved, but Wi-Fi VIP reachability
failed. Acceptance withheld; follow the agreed rollback and revalidate the baseline before another
attempt." Include an owner and diagnostic next step in the private record, not a claim of success.

Record each temporary server PID, address, route, rule and workload file when created. Clean only
those exact resources and verify removal; do not kill processes by name or delete a shared tree.
Distinguish temporary benchmark state from persistent intended configuration. Preserve the baseline
and failed-path evidence in private documentation while removing temporary payloads and credentials.

The local example checks validate documentation structure only. They prove no negotiation, DHCP,
routing, failover, service reachability or network performance; those need separate live approval.
