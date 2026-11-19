# Dedicated Storage Network Reference

Use this reference when adding a faster storage interface to a host that must retain an existing
management/control-plane interface, or recovering storage clients after a network interruption.

## Desired Shape

```text
management interface
├── established management subnet/address
├── global default route
├── control-plane or k3s node traffic
└── fallback service endpoint

storage interface
├── dedicated VLAN/subnet
├── fixed DHCP reservation
├── no global default route
├── ignored DHCP DNS
├── source policy table/rule
└── primary storage endpoint
```

Do not describe two interfaces as automatic failover unless a tested DNS, bonding, VRRP or
application-level mechanism actually implements failover. Two reachable addresses provide a manual
fallback only.

## Source Policy Routing

Separate subnets do not by themselves guarantee symmetry. If a storage service receives a connection
from a client on the management subnet, Linux may prefer the directly connected management route for
the reply.

Generic NetworkManager profile additions:

```text
secondary subnet route in table <table-id>
default via <storage-gateway> in table <table-id>
rule priority <priority> from <storage-address>/32 table <table-id>
```

Verify:

```bash
ip route get <management-client-ip> from <storage-address>
```

The result must show the storage gateway and storage interface.

## UniFi Application Order

1. Check every existing network and VPN range.
2. Create the routed Storage VLAN and DHCP scope.
3. Identify the direct endpoint port from the client connection field.
4. Prepare the host profile without activating it.
5. Set the direct port's native network to Storage.
6. Let the client receive one guarded DHCP lease if necessary.
7. Create the fixed reservation from the live client record.
8. Renew DHCP and confirm the expected address.
9. Add source policy routing and service allow lists.

A client VLAN override is not required when the direct access port already uses Storage as its native
network. Adding both can generate misleading controller warnings or duplicate policy.

## Link-Speed Troubleshooting

For a USB multi-gig adapter:

```bash
lsusb -t
ethtool <interface>
ethtool -i <interface>
```

Record:

- USB negotiated speed;
- USB driver and firmware;
- supported and advertised Ethernet modes;
- link-partner advertised modes;
- current speed/duplex;
- recent carrier/reset events.

If the adapter previously negotiated multi-gig but falls to 1 Gb/s after a port change:

1. confirm UniFi did not reset the port mode;
2. keep the switch port on a compatible Auto setting unless the exact transceiver requires a
   supported manual host-side mode;
3. restart normal endpoint auto-negotiation;
4. renew DHCP after carrier stabilizes;
5. require both the expected speed and address.

Carrier alone is insufficient. A forced host-side SFP+ rate can leave the copper adapter reporting
carrier while DHCP and data fail.

## Benchmark Matrix

Capture these stages separately:

| Stage | Purpose |
| --- | --- |
| Existing management NIC | Baseline uplink and workload |
| Temporary direct-L2 secondary NIC | Maximum adapter/switch path without routing |
| Permanent routed VLAN before policy | Expose asymmetric return-path mistakes |
| Permanent routed VLAN after policy | Real supported production result |

For aggregate uplinks, use several simultaneous peers and sum throughput. Run both directions.
Repeat the real file protocol using scoped temporary files. Do not compare `iperf3` directly with
filesystem throughput without identifying disk, cache, protocol and routing limits.

## Failure Patterns

| Symptom | Likely cause | Check |
| --- | --- | --- |
| Service works locally but not from one Wi-Fi client | Duplicate-subnet ARP/L2 ambiguity | Client ARP entry, host interfaces, MetalLB announcer |
| `iperf3` is fast but SMB stays near 1 Gb/s | Asymmetric replies through management | Source-specific `ip route get` |
| Link shows carrier but DHCP times out | Incompatible forced switch/transceiver rate | Partner modes, switch Auto, DHCP logs |
| Reservation exists but host gets a random IP | Reservation attached to stale/wrong network record | Live lease network, stale client entry |
| MAC appears on several ports | MAC learned across uplinks | Client Connection field and connected endpoint |
| Second NIC changes default route/DNS | DHCP profile not constrained | `never-default`, ignored DNS, route metric |

## Service Validation

Before declaring success:

- primary storage address accepts authenticated create/read/delete;
- management fallback still works;
- application LoadBalancer/Ingress endpoints work from actual clients;
- storage and management routes are correct;
- backup targets remain Available;
- no temporary benchmark state remains;
- configuration management is idempotent.

## Post-Outage NFS And Backup Recovery

Separate the network trigger, persistent client state and backup capacity faults:

1. Correlate physical carrier changes and NFS lease/timeout errors across clients and server in UTC.
   Simultaneous link loss suggests a shared network event, not proof of a particular switch action.
2. Compare node CPU with container CPU, child commands and process creation rate. A controller can
   appear quiet in lifetime `ps` averages while repeatedly spawning expensive, short-lived backup
   commands. Inspect the deployed version's retry path before attributing this to useful backup work.
   After a restart, filter CPU rates to the replacement pod; old pod samples can remain in the rate
   window and falsely suggest that the new controller is still saturated.
3. Read the same existing metadata file locally on the server and through the failing client's
   actual mount namespace. Carrier, file attributes, an Available backup target and healthy volume
   replicas do not prove file data is readable. Server reads succeeding while client reads return
   `EIO` distinguishes a client-path fault from proven server-file corruption.
4. Inspect the export's backing filesystem and project quota separately. With ext4 project quotas,
   `df` inside a project can show a quota-limited size while `df` at the filesystem root still shows
   ample space. `repquota -P -s <mountpoint>` exposes usage, soft/hard limits and grace; an expired
   soft-limit grace blocks writes before the hard limit is reached.
   Monitor quota usage, limits, remaining headroom and raw grace deadlines independently of PVC
   and filesystem alerts, including missing/stale collection. A fleet-wide node-exporter textfile
   collector needs its directory on every exporter node, even nodes without quotas; verify zero
   textfile scrape errors fleet-wide rather than accepting one healthy quota-host scrape.
   Verify receiver-visible text as well as rule firing: summary-only receivers need current usage,
   soft/hard limits and headroom in the summary, scoped to the alerting instance and project.
   Assert rendered annotations with synthetic metrics, including identically named projects on
   different hosts; missing supporting metrics must be explicit, not mistaken for zero usage.
5. Estimate catch-up upload growth before starting large backups, not only current store usage.
   With approval, restore quota headroom and synchronize the configuration-management source.
   Raising a soft limit does not raise the hard cap; expanding that cap or an aggregate allocation
   budget needs explicit approval. Preserve existing recovery points until a fresh backup is
   verified; never delete backing block files or strip finalizers to silence a stuck deletion.
6. Establish mount ownership and propagation before recovery. If backup-store mounts are private to
   a Longhorn manager container, no backups are actively transferring, and volume engines run
   independently, gracefully recreate one manager pod as a canary. Do not restart the DaemonSet
   fleet, unmount workload/PVC data paths, force-delete pods or reboot nodes as a shortcut.
7. Manager recovery does not refresh engine-side backup clients. If new backups still return `EIO`,
   inspect instance-manager namespaces separately. With no backup/restore operations active and an
   exact, private backup-store mount identified, a normal unmount followed by the deployed engine
   CLI's inspection of a known completed backup can recreate that mount without restarting volume
   engines. Stop if the unmount is busy; never use force/lazy unmount or restart an instance manager
   to bypass this check.
8. Require a real metadata read, deletion progress, settled CPU/process creation, unchanged volume
   health and control-plane quorum before continuing one manager at a time. Startup readiness alone
   is insufficient. Verify newly completed backups for the protected volume set, not merely an empty
   pending queue or some successful volumes in a partially failed batch. Retry capacity-blocked
   backups through the supported backup policy after headroom is restored.

Record original quota values and workload health before writes. Do not reduce a raised limit below
current usage as an automatic rollback. If the mount is shared or recovery fails, stop and establish
its active users before proposing remount or service maintenance. An application filesystem can
have checksum errors while its replicated block volume reports healthy; assess it separately and
never run a repairing filesystem check on a mounted volume.
