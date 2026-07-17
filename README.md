# Ninjasu Documentation Vault

This is the **canonical knowledge source** for the Ninjasu platform: one shared backend
(`ninja delivery service java`) serving three clients — the customer app
(`Food-Ninja-Frontend`), `Ninjasu_Web`, and `Ninjasu_Rider_App`. It is an Obsidian
vault and a git repo, checked out as a sibling of those four repos.

This page is the system's own memory of itself — read it before adding anything, so the design
doesn't get silently reinvented or drifted away from.

## Why a separate vault, and not docs inside each repo

One backend, multiple clients, one set of business rules. A rule documented inside the frontend
repo is invisible to whoever builds the rider app next — they'd either re-derive it from Java, or
worse, guess. Putting shared knowledge in one place that every repo points at means it's written
once and true everywhere. Per-repo tooling docs (each repo's own `CLAUDE.md`, `skills/`) stay in
their repos — only *knowledge that outlives a single repo* lives here.

## How it works — two layers, never conflated

| Layer | Answers | Mutability | Lives in |
|---|---|---|---|
| **Living docs** | "What is true *now*?" | Mutable — update in place, no history append | `01-Architecture/principles.md`, `02-Domain/*`, `03-Backend/*`, `04`–`06` |
| **Decision log (ADRs)** | "*Why* did we choose this, and what did it replace?" | Immutable — never edit an accepted ADR, only supersede it with a new dated one, linked both ways | `01-Architecture/decisions/ADR-NNNN-*.md` |

**The trail, without duplication:**
- **ADR** = why we decided (once, forever, in the vault)
- **Commit message** (`Refs ADR-NNNN`) = why this specific diff
- **Living doc** = what's true right now

If you're tempted to write a `plan-v2.md` to track a changed decision — don't. Write a new ADR
that supersedes the old one. That *is* the trail; a pile of plan files isn't.

## How to use this vault

1. **Clone convention:** all four repos and this vault are siblings under one parent folder.
   Each repo's `AGENTS.md` points here via `../Ninjasu_Documentation/` — and also carries this
   vault's git URL, so a lone/isolated checkout can self-heal by cloning the vault instead of
   silently losing all doc access.
2. **Start at [`00-Maps/Home.md`](00-Maps/Home.md)** — it links to a hub note (MOC) per app.
   Each app's MOC links only to what that app needs: its own section plus the shared
   Architecture/Domain/Backend docs relevant to it.
3. **Use markdown links (`[text](path.md)`) as the primary form**, not `[[wikilinks]]`. This vault
   is read by three things — Obsidian, GitHub's web UI, and an AI agent reading raw files —  and
   only Obsidian resolves wikilinks. Wikilinks are fine as a secondary convenience inside Obsidian
   itself, never as the only path to a doc.
4. **A doc references code by a stable ID, never a file path** — see
   [`90-Meta/maintenance-guide.md`](90-Meta/maintenance-guide.md) for the `ADR-NNNN` convention
   threaded through code comments, commit trailers, and ADR filenames.

## How to record something new

| You just… | Do this |
|---|---|
| Made an architectural/cross-app decision | New ADR in `01-Architecture/decisions/`, from `90-Meta/templates/adr-template.md`. Never edit an existing accepted ADR. |
| Changed a shared business rule (menu, cart, pricing…) | Edit the living doc in `02-Domain/` directly — in place, no history append. |
| Learned something about one specific app | Edit that app's `0{4,5,6}-*-App/` section. |
| Built a feature that's still being designed | `90-Meta/templates/feature-template.md` in `07-Roadmap/`, `status: designing`. Promote its decided parts into an ADR once locked. |
| Found a fact that's owned by code (a DTO shape, a field type) | **Don't transcribe it.** Link to the code as source of truth. Vault docs describe the *rule*, not the *shape* — the shape drifts the moment someone edits the DTO without touching the doc. |

## The rules this vault runs on

These came out of an explicit devil's-advocate pass before the vault was built — each one is a
concrete failure mode this design would otherwise hit. They are law, not suggestions:

1. **Self-healing pointer** — every repo's `AGENTS.md` carries this vault's git URL, not just a
   relative path. An isolated checkout must be able to reconnect, not go dark.
2. **Reference, never transcribe code-owned facts** — a doc that hand-copies a DTO field list will
   drift from the code the moment either changes without the other.
3. **Reference audit before any delete** — when a doc moves, every place that pointed at its old
   location (other repos' `CLAUDE.md`/`skills/`/`code_map.md`, in-code comments) gets rewritten in
   the same pass, not left dangling.
4. **Markdown links primary** — this vault has three readers; only one understands `[[wikilinks]]`.
5. **Secrets never enter this repo** — `keys/`, `*.keystore`, `*credentials*`, `.env*` stay
   repo-local and gitignored. See the vault's own `.gitignore` and
   `90-Meta/maintenance-guide.md` for the full exclusion list.
6. **ADR ceremony is right-sized to team size** — a small/solo team doesn't need heavyweight
   review gates; git history is the immutability backstop. Scale ceremony up as the team grows.
7. **Anchor-existence gate** — staleness checking must confirm an `anchors:` code path still
   exists before trusting an empty diff as "nothing changed." A renamed/deleted anchor with no
   existence check reads as falsely fresh forever.
8. **`verified_against` only moves with a real edit** — never bulk-stamped, only bumped in the
   same commit that actually re-reads and updates the doc.
9. **A missing sibling repo is "unverifiable," never "fresh"** — `/sweep` run without access to a
   repo it needs to check must say so loudly, not silently pass.
10. **This vault never states file locations as its main content** — that's `code_map.md`'s job,
    per repo. This vault states *why*, code_map states *where*. See the ownership table in
    `90-Meta/maintenance-guide.md`.

## Structure

```
00-Maps/            Hub notes (MOCs) — start here
01-Architecture/     Long-horizon principles + decisions/ (ADRs)
02-Domain/           Shared business rules (menu, cart, wishlist, core, captain-ordering…)
03-Backend/          API contracts, data model, auth — backend-owned, cross-client
04-Customer-App/     Customer app (Food-Ninja-Frontend) specific knowledge
05-Web/              Ninjasu_Web knowledge — admin + shop dashboards, marketing, guest (stub)
06-Rider-App/        Rider app specific knowledge (stub — being built)
07-Roadmap/          Backlog, loopholes, in-progress feature specs, pending flags
08-Ops/              Deploy, signing, docker — references, never secrets
90-Meta/             This guide, templates, the rules above
attachments/         Non-markdown assets (SQL files, images)
```

## Maintenance

See [`90-Meta/maintenance-guide.md`](90-Meta/maintenance-guide.md) for the full mechanics: named
drift triggers, the `/sweep` staleness algorithm, and the code↔doc reference convention.
