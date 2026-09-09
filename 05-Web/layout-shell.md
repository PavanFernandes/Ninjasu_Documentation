---
id: ""
title: "Ninjasu Web — App Shell & Scroll Ownership"
summary: "How AppShell owns page scrolling (single scroll container: <main>) and the double/triple-scroll bug that happens when a page or the document competes with it."
type: how-to
status: active
apps: [web]
module: "layout-shell"
anchors: ["Ninjasu_Web/src/shared/components/AppShell.tsx", "Ninjasu_Web/src/app/layout.tsx"]
verified_against: "web@b5c0cc876c49c1678a23971becc14108f48028fd"
updated: 2026-09-09
---

# Ninjasu Web — App Shell & Scroll Ownership

## What AppShell owns

Every authenticated shop/admin page renders inside `AppShell`
(`src/shared/components/AppShell.tsx`): a fixed-height shell (`h-full flex-col overflow-hidden`)
with a sticky header, a sticky sidebar, and exactly **one** scrolling region —
`<main className="min-h-0 flex-1 overflow-y-auto p-4">`. Page content renders into that `<main>`;
it is the single, canonical scroll owner for the whole authenticated app. No page should introduce
its own top-level scroll container that competes with it.

## The rule

**Only `<main>` scrolls.** For this to hold:

- `<html>`/`<body>` (`src/app/layout.tsx`) must be locked to `h-full ... overflow-hidden` — not just
  `min-h-full`. Without this, once a page's content exceeds the viewport, the *document* itself
  becomes a scroll container underneath everything else: the header and sidebar visibly drag upward
  with the page instead of staying pinned, because they're no longer anchored to a non-scrolling
  `<body>`.
- Every flex ancestor between the shell root and `<main>` needs `min-h-0` on its flex children — a
  flex item's default `min-height: auto` (its own content's intrinsic size) wins over `flex-1`, so
  without it a tall page forces the row to grow past the shell instead of clamping to it.
- A page that wants a bounded, independently-scrolling sub-region (e.g. a table with a sticky header,
  scrolling just that section while filters/context stay visible) must not do it with a
  viewport-relative magic number like `max-h-[calc(100vh-230px)]`. That number is a guess at
  everything above it (header height, padding, filters); any drift leaves a sliver of overflow that
  `<main>` picks up too — two scrollbars fighting over a few pixels. Do it by flowing a real height
  down instead: `h-full` on the page's `<main>` wrapper → `flex h-full min-h-0 flex-col` on the
  screen root → `min-h-0 flex-1` on the growing region → `h-full overflow-y-auto` on the actual
  scroll box. The box then always exactly fills whatever space is left, never more, never less.

## Incident

Ninjasu_Web's Purchases → Materials tab
(`features/shop/components/purchases/MaterialsTab.tsx`) hit two of these failure modes at once
(2026-09-09): `<body>` had `min-h-full` with no `overflow-hidden`, so the whole document scrolled
and dragged the header/sidebar up with it; MaterialsTab's own `max-h-[calc(100vh-230px)]` box added
a second, independently-scrolling region on top. Net result: three visible scrollbars. Fixed by
locking `<body>` + the shell root to `h-full overflow-hidden` and letting the table flow through
`<main>`'s single scroll rather than bounding itself with a guessed constant.

## When debugging "multiple scrollbars"

Check `app/layout.tsx`'s `<html>`/`<body>` classes **first**, before reasoning about flexbox
internals further down the tree. A shell component having `overflow-hidden` on its own root div
does not guarantee `<body>` can't also scroll.

## Related

- [Ninjasu_Web stack ADR](../01-Architecture/decisions/ADR-0017-ninjasu-web-stack-and-auth.md)
- [Web App MOC](../00-Maps/Web-App-MOC.md)
