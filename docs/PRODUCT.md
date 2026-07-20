# CoKeep — product & UX notes

## Brand

**CoKeep** — keep shared places in good shape, together.

Visual direction: calm Nordic “fjord” teal on soft mist gradients (not purple, not cream/terracotta). Brand name uses a serif display face; UI uses rounded system typography.

## Information architecture

1. **Objects** — home list of co-owned properties  
2. **Object hub** — segmented: To-dos · Costs · Reports · People  
3. **Invites** — pending cooperation requests  
4. **Profile** — identity, avatar, sign out  

First-time path: Welcome → Register → empty Objects → Create (Cabin/Generic template) → invite co-owners.

## UX principles applied

- One primary action per screen (create, invite, log work, add cost).
- To-dos split into **Open** (due-first) and **Done** — no cluttered single list.
- Work duration visible on the row; full log only after opening an item.
- Assignee change is a one-tap menu on the detail screen.
- Reports combine a large total, a bar chart, then a per-person and detail list.
- Motion is limited to welcome entrance, object list stagger, and atmospheric background drift.

## Templates (v1)

| Template | Default lists |
|----------|----------------|
| Cabin | Maintenance, Seasonal, Shopping |
| Generic | To-do |

## Integrations (pluggable)

| Concern | Dev behavior | Production |
|---------|--------------|------------|
| Invites (new users) | iOS opens Messages with prefilled body | Same |
| Email reset | Console log | SMTP |
| Push | Console + in-app Notification rows | APNs |
| Launch splash | Disabled by default | `/admin` + `ADMIN_*` env |
