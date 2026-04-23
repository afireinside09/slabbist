# Sub-project 1 — Auth & store/team model

The identity & tenancy foundation. Nothing else persists without this.

## Scope

- Supabase Auth (email + password; magic link / OAuth optional follow-up).
- `stores` entity — each store is a tenant. Auto-created on signup for MVP.
- `store_members` entity — user ↔ store membership with a role (`owner`, `manager`, `associate`).
- Row Level Security policies scoped by `store_id` across every tenant table.
- **MVP behavior:** user signs up → a store is auto-created → user is the `owner`. No invite flow, no role switcher.
- **Post-MVP:** invite flow, role management UI, transferring ownership, leaving a store.

## Features captured

- Multi-employee accounts under a single store
- Role-based permissions (owner, manager, associate)
- Margin visibility controls — owners see cost/margin, associates see buy price only (enforced at the query layer via RLS + view filters)
- Shift handoff notes (owner/manager scratchpad visible to next-shift)

## Dependencies

None — foundational.

## Unblocks

All other sub-projects that write tenant data.
