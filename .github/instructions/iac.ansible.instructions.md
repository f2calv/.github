---
description: 'Ansible conventions for playbook and role layout, idempotence, rolling node maintenance, inventory variables and secret handling.'
applyTo: '**/ansible/**,**/playbooks/**,**/roles/**'
---

# Ansible

Ansible is the escape hatch for what a declarative platform cannot own — bringing a bare host to the
point where the platform takes over, and maintaining it thereafter. Keep it to that role.

## Layout

```text
ansible/
├── playbook.yml                  # Entry point; one play per host group
├── launch.sh                     # Documented invocation examples
├── .env.example                  # Tracked template for required variables
├── inventories/
│   └── hosts.yml                 # Hosts, groups and per-host variables
└── roles/
    └── <role>/
        ├── tasks/
        │   ├── main.yml          # Imports the task files, in order
        │   └── <concern>.yml     # One file per concern
        ├── handlers/main.yml
        ├── vars/main.yml
        └── files/
```

- One task file per concern, imported in explicit order from `tasks/main.yml`. The import list is the
  readable summary of what the role does, so keep it ordered and commented where order matters.
- Comment out an import rather than deleting it when a step is only needed occasionally, such as a
  one-off bootstrap, and say why in a comment directly above.

## Task Authoring

- Use fully-qualified collection names (`ansible.builtin.command`, not `command`), so a task cannot
  be captured by a same-named module from another collection.
- Give every task a `name` that states what it achieves. The name is the operator-facing log.
- Write idempotent tasks. Prefer a module that converges state over a shell command that repeats work.
- Where a command must be used, set `changed_when` and `failed_when` explicitly rather than letting
  Ansible infer change from an exit code.
- Guard a task that depends on prior state with a `stat` (or equivalent) check and a `when` condition,
  so a first run and a repeat run both behave correctly.
- Use `tags` on any task group that is worth running standalone, and document the invocation.
- Use handlers for a restart or reboot triggered by a change, and `ansible.builtin.meta: flush_handlers`
  where a later task depends on that restart having completed. Ordering bugs here are silent.

## Inventory and Variables

- Drive per-host behaviour from inventory variables rather than branching playbooks. A host that needs
  extra hardware setup should declare a variable, not require its own play.
- Default every optional variable at the point of use (`| default(false) | bool`) so a host that omits
  it still converges.
- Keep the inventory the single description of the estate. Do not hardcode a hostname or address in a
  task.

## Rolling Maintenance

- Set `serial: 1` when a play maintains the nodes of a clustered service, so the cluster never loses
  more than one node at a time.
- Drain a node before disruptive work and restore it afterwards. Put the restore step in an `always`
  block so a failed play does not leave a node cordoned.
- Make the drain and restore conditional on the platform actually being installed, so the same play
  works on a fresh host and an existing one.
- Delegate cluster-level commands to a control-plane host rather than assuming the target can run them.

## Running

- Support a dry run and document it: check mode with a diff shows what would change without changing it.
- Support limiting a run to one host, so a node can be added or repaired without touching the estate.
- Document the required environment variables and connection prerequisites at the top of the entry
  point or in the launch script, not in tribal knowledge.

## Secrets

- Never commit a token, password, join secret or registry credential. Track a `.env.example` listing
  every required variable with placeholder values, and gitignore the real file.
- State what each credential is for and the minimum scope it needs.
- Source secrets from the environment or a vault at run time. Never write a resolved secret into a
  task name, a log line, a registered variable that is later printed, or a committed file.
- Never commit an inventory containing real addresses, user names or host names where the repository
  is public. Keep it private or template it.
