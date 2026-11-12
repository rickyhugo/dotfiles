---
name: setup-pstack
description: Configure pstack's models and reasoning settings by use case, with shared choices and per-machine overrides. Use for setup-pstack, configure pstack models, pstack budget, or changing model choices.
---

# Setup pstack

## 1. Read current choices

Read the [configuration format](../../docs/configuration.md), bundled role
defaults, and existing shared and machine-local files. Show the effective role
table, including inherited choices and missing mappings. Read files directly;
setup needs no generated rules or config program.

## 2. Choose the scope and models

Ask whether to change shared choices or this machine only. Default to the local
file. Preserve unrelated profiles, targets, roles, and options.

Ask which use cases to configure and the user's cost/latency preference. Offer
confirmed models alongside `inherit`. Reasoning and speed are explicit settings,
not suffixes inferred from a generic budget. Confirm availability and model
selection support before proposing choices. List roles preserve order and count;
repeated profiles are separate attempts. The judge pool may be empty.

## 3. Confirm and save

Show the destination, proposed diff, and resulting role choices. After approval,
edit only that JSON file. A local role can reference a shared profile. Replacing
a profile replaces all its targets, so retain the targets the user wants to keep.
Migrate a legacy model rule only when asked; preserve it until removal is approved.

## 4. Check

Re-read both layers and check version, role names, profile references, ordinary
versus list role shapes, and effective choices. Confirm each panel's seat count.
Report unmapped models and unsupported options. Show the saved choices. They
apply at the next read, without a restart.

## 5. Offer project verification

If the project has no way to drive its real app, offer once to generate one with
the sibling `create-verification-skill`. If correctness needs a model checker or
proof and none exists, offer `create-formal-verification-skill`. Generate neither
without approval.
