---
id: ADR-0007
type: decision
status: accepted
apps: ["backend","customer"]
module: "menu"
anchors:
  - { repo: backend, path: "src/main/java/com/example/ninja/entity/Addon.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/service/impl/AddonGroupServiceImpl.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/service/impl/MenuItemServiceImpl.java" }
  - { repo: customer, path: "src/features/restaurant/components/AddonSheet.tsx" }
  - { repo: customer, path: "src/features/admin/components/SharedAddonsTab.tsx" }
verified_against: "backend@ff5ade334891238d16b8010e372fdbbc502c193e, customer@49f04f81d4853953686a33f7e644ed7944749951"
updated: 2026-06-22
---

# ADR-0007: Per-Option Images for Shared Addons

## Context

`addons` rows carried name and price only. Admin asked for a photo per shared-addon
option (e.g. Boiled Egg, Raita under a "Sides" group) so customers see thumbnails in the
customize sheet. The granularity choice was PER OPTION rather than per group — matching
the Swiggy/Zomato pattern where each individual addon option can carry its own thumbnail.

## Decision

An `image_url` column (TEXT, nullable) is added to the `addons` table, so it lives on
**every** addon — ITEM-scoped or SHARED — not just shared ones. The admin image picker is
exposed only in the Shared Addons tab for now; ITEM-scoped addons simply carry NULL. This
keeps the column universal and forward-compatible without building a second picker
up front.

No migration was needed — `ddl-auto=update` auto-creates the column. NULL means "no
image," which is also the existing behaviour at every read site: the backend's URL builder
returns null for a null key, and the frontend renders a thumbnail only when a value is
present, never passing a null uri to an `<Image>` component.

Image upload reuses the existing presigned-S3 flow, under a dedicated `addons` folder
(mirroring the existing `menu-items` folder convention). The frontend stores the returned
key in local option state and sends it as `imageUrl` on save; save is blocked while any
option's upload is still in flight.

S3 key/URL handling follows the platform's standard compliance pattern: the write path
strips the full URL down to a bare key before persisting (on create, add, and update of an
addon), and the read path expands the stored key back to a full URL in **both** places an
addon DTO gets built — the shared/menu addon mapper and the separate mapper used by the
item-create response. That second mapper is a known duplicate-DTO-construction site and
was deliberately not skipped.

The new `addon.imageUrl` field was added to the shop menu read endpoint and to the
addon-group create / per-option endpoints.

## Consequences

This makes it easy to add per-option thumbnails anywhere addons are read, without a schema
change, since the column is already universal. It rules out group-level-only imagery (a
group can't have one photo covering all its options) — per-option was the deliberate
choice to match competitor UX. It also means item-scoped addons carry a permanently-NULL
column today, accepted as forward-compatible headroom rather than dead weight; enabling
images for item-scoped addons later needs only a UI picker, not a data model change. Any
new addon DTO mapper added in the future must remember to expand the image key, or it will
silently regress to missing thumbnails for that surface only.

## Enforced in

- `Addon` entity: `image_url` column definition.
- `AddonGroupServiceImpl`: key-stripping on `addAddon` / `updateAddon` / the addon-group
  save path, and key-expansion in its addon DTO mapper (shared/menu listing).
- `MenuItemServiceImpl`: key-expansion in its separate addon DTO mapper used by the
  item-create response — the duplicate mapper that must stay in sync with the one above.
- `AddonSheet.tsx` (customer): renders the option thumbnail only when `imageUrl` is
  present.
- `SharedAddonsTab.tsx` (admin): the image picker UI, upload-in-flight save guard, and
  key/URL round-trip for shared addon options.

---
*Immutable once accepted. If this decision changes, write a new ADR and mark this one `status: superseded` with a link forward.*
