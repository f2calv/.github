# Dedicated Storage Network Reference

Use this reference when adding a faster storage interface to a host that must retain an existing
management/control-plane interface.

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
