---
name: unifi-network-management
description: 'Discover, design, change, benchmark and recover UniFi-managed networks safely. Use for VLANs, DHCP reservations, switch-port native networks, multi-NIC Linux hosts, dedicated storage networks, routing asymmetry, MetalLB/ARP incidents, and before/after network performance validation.'
argument-hint: '[mode={audit|plan|apply|benchmark|recover}] [client-or-port] [network-purpose]'
user-invocable: true
compatibility: 'Requires an authenticated UniFi Network browser session for controller changes. Host validation may additionally require SSH, NetworkManager, iproute2, ethtool and iperf3.'
---

# UniFi Network Management

## Overview

Make UniFi and endpoint-network changes without losing management access, introducing Layer 2
ambiguity or measuring the wrong path. Separate controller state, switch-port state, endpoint state
and application behavior; each can look healthy while another layer is wrong.

Keep real networks, VLAN IDs, addresses, MACs, switch names, port numbers and household client data in
the owning private infrastructure repository. This skill carries only the reusable workflow.

Use [the storage-network reference](references/storage-network.md) for dual-NIC NAS and benchmark
patterns.

## Safety Model

- `audit` and `plan` are read-only.
- `apply` changes the live network. Obtain explicit approval for the proposed network, subnet,
  switch port, reservation and endpoint behavior.
- Capture management access, default routes, application health and rollback values before a write.
- Make one control-plane change at a time and verify its effect before continuing.
- Let the user enter UniFi credentials in the shared browser. Never request, record or replay them.
- Never bridge two physical interfaces merely to provide fallback. A bridge can create a real Layer
  2 loop; two routed interfaces do not.
- Never place two ordinary host interfaces in the same subnet without a deliberately designed
  advanced-routing requirement. Expect ARP flux, asymmetric routing and service advertisement
  ambiguity.
- A DHCP reservation does not place a device in a VLAN. Port native-network or client VLAN
  configuration must also be correct.
- Do not treat switch Auto negotiation, endpoint carrier and actual negotiated speed as equivalent.
  Verify the endpoint with `ethtool`.

## Responsibility Boundary

| Layer | Authority |
| --- | --- |
| Networks, VLAN IDs, DHCP pools, reservations, switch ports | UniFi |
| Interface profile, default-route suppression, DNS behavior, policy routing | Endpoint configuration management |
| Service allow lists and listener behavior | Service configuration |
| Current topology, allocations, measurements and recovery notes | Private infrastructure documentation |

Do not encode controller-managed VLAN or reservation data as an unrelated host-static address. Do not
make endpoint configuration depend on a transient interface name without also guarding the hardware
MAC.

## Workflow

### 1. Establish The Existing State

Inspect read-only before proposing a design:

1. Existing networks, VLAN IDs, subnets, DHCP ranges and gateways.
2. VPN, Teleport, guest or other configurations that reserve hidden subnets.
3. Client identity, MAC, current IP, network and direct switch/port.
4. Host interfaces, addresses, routes, rules and active network manager.
5. Switch topology and uplinks.
6. Application health through every user-facing path that must survive.
7. Baseline link speed and throughput.

UniFi may reject an apparently unused subnet because a dormant VPN server reserves it. Treat the
validation error as authoritative; do not delete the VPN configuration merely to reuse its range.

### 2. Identify The Endpoint Port Correctly

A MAC can appear on:

- its direct endpoint port;
- inter-switch uplinks;
- gateway uplinks;
- stale client or topology records.

Prefer the client table's **Connection** field to locate the direct switch and port. Cross-check the
port's connected client before changing it. Never select a port solely because the MAC appears in a
global ports table.

If the controller still shows an old IP/network after a move, distinguish stale client metadata from
the current DHCP lease and endpoint address. Remove only the stale client record when required; do
not remove the live reservation or unrelated client history.

### 3. Design The Change

For an additional host interface:

- keep the established management interface and k3s/control-plane address unchanged;
- put the new interface in a distinct subnet;
- keep the global default route on management;
- prevent storage/secondary DHCP from installing DNS or a default route;
- use source policy routing when replies must leave through the interface that owns the source IP;
- document a fallback endpoint separately from automatic failover.

For a new network, select a VLAN/subnet only after overlap checks against every existing network,
VPN pool and route.

### 4. Apply In Safe Order

Preferred sequence:

1. Create the UniFi network and DHCP scope.
2. Create or confirm the endpoint's fixed DHCP reservation.
3. Prepare the host profile with activation disabled.
4. Change the verified direct switch port's native network.
5. Activate the host profile.
6. Verify address, link, routes and rules.
7. Update service allow lists/listeners.
8. Retest applications.

When UniFi cannot create a reservation before the client joins the target network, allow one guarded
DHCP lease, create the fixed reservation from that live client record, then renew the endpoint.

### 5. Configure Linux Endpoints

For NetworkManager, a secondary routed interface normally needs:

- profile bound to interface and MAC;
- `connection.autoconnect yes`;
- `ipv4.method auto`;
- `ipv4.never-default yes`;
- `ipv4.ignore-auto-dns yes`;
- route metric higher than management;
- IPv6 disabled unless explicitly designed;
- source policy rule/table when clients live behind another interface's directly connected subnet.

Validate:

```bash
ip -br address
ip route show default
ip rule show
ip route show table <table-id>
ip route get <management-client> from <secondary-address>
ethtool <secondary-interface>
```

The global default must still use management. The source-specific query must use the secondary
gateway/interface.

### 6. Protect MetalLB And Other L2 Services

Adding a second interface in the service's LAN can change ARP advertisement behavior even when the
new interface has no default route. If a MetalLB service becomes client-specific or intermittent:

1. Test the pod, ClusterIP/endpoint, LoadBalancer IP and public ingress separately.
2. Inspect the client's ARP entry for the VIP.
3. Remove the duplicate same-subnet interface/address.
4. Refresh the relevant L2 advertisement only if needed.
5. Retest from wired and Wi-Fi clients.

A `200` response from the node does not prove a Wi-Fi client learned the correct VIP MAC.

### 7. Validate Link Negotiation

Check both sides:

```bash
ethtool <interface>
lsusb -t
```

Confirm:

- USB generation/driver;
- advertised endpoint modes;
- link-partner modes;
- negotiated speed and duplex;
- carrier stability and reset/error logs.

Do not force endpoint settings the driver rejects. For copper adapters behind an SFP+ transceiver,
forcing the switch host-side rate can show carrier while breaking DHCP/data. Prefer compatible switch
Auto settings and restart standard endpoint auto-negotiation when a supported link falls back.

### 8. Benchmark Before And After

Use at least two layers:

1. `iperf3` for network capacity.
2. The real protocol/workload, such as concurrent SMB transfers.

One 1 GbE peer cannot prove a 2.5 GbE uplink. Use several simultaneous peers or one faster peer.

Requirements:

- bind tests to the intended source/address;
- use one server port per simultaneous `iperf3` client;
- start temporary servers and record exact PIDs;
- create uniquely named temporary workload files;
- remove every PID, address, route, rule and file afterward;
- record throttling, errors and application impact;
- distinguish direct-L2 throughput from routed/VLAN throughput.

### 9. Verify And Roll Back

After every apply:

- endpoint has expected IP and physical speed;
- management default route is unchanged;
- source policy route is symmetric;
- approved clients reach the service;
- critical applications remain healthy;
- no unexpected USB/link resets or throttling occurred;
- configuration management reports `changed=0` on a second run.

Rollback order:

1. deactivate the secondary endpoint profile;
2. restore the previous switch-port native network and link setting;
3. remove the new reservation/network only after clients are gone;
4. confirm management, applications and L2 services;
5. preserve diagnostic evidence in private documentation.

## Completion Report

Report:

- controller/network and endpoint changes;
- management and secondary addresses;
- default and policy-route results;
- negotiated link;
- before/after network and workload throughput;
- application checks;
- cleanup confirmation;
- remaining soak, firewall, DNS or failover work.

