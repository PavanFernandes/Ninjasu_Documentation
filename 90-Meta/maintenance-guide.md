---
id: ""
type: reference
status: active
apps: [backend, customer, admin, rider]
module: meta
anchors: []
verified_against: ""
updated: 2026-07-11
---

# Maintenance Guide

This vault only stays trustworthy if drift is caught at named triggers, not by hoping someone
remembers. This page names the triggers and the mechanism that catches each one.

## Ownership split — do not blur this

| Mechanism | Owns | Scope | Kept fresh by |
|---|---|---|---|
| `<repo>/skills/code_map.md` (each repo) | **WHERE** a file is | per-repo | that repo's Stop hook (grep-persistence rule) |
| This vault | **WHY** — the rule, the decision, the domain behavior | cross-repo | `/sweep` (see below) |

**The vault must never state a file location as its main content.** If a doc needs to say where
something is enforced, that's the `anchors:` frontmatter field or the "Where it's enforced"
section — a pointer, not a copy of code_map's job. If you catch a vault doc turning into a file
directory, that's the ownership split failing — fix it by deleting the location list and adding
an `anchors:` entry instead.

## Named drift triggers

| When this happens | Do this, same PR/commit |
|---|---|
| Backend DTO/entity field changes | Update the frontend type in the same task (existing rule, ARCHITECTURE.md). If a vault doc describes that shape, it must **link** to the DTO, never hand-copy fields — code is the source of truth for shape. |
| A design choice gets made (schema, architecture, cross-app contract) | Write a new ADR **before** merging the code that implements it. Never edit an accepted ADR — supersede it. |
| A `Modules/*` rule changes | Update the living doc in `02-Domain/` directly (mutable, in place — no history append). |
| A file referenced by `anchors:` is renamed/moved | Update the `anchors:` path in the same commit that does the rename. |
| A doc's `anchors` code hasn't been touched since `verified_against` | Nothing to do — the doc is still current by construction. |

## `/sweep` — how staleness gets checked

Each doc's frontmatter carries:

```yaml
anchors:
  - { repo: backend, path: src/main/java/.../CartServiceImpl.java }
verified_against: af77a17   # code SHA this doc was last confirmed against
```

`/sweep` (see `Food-Ninja-Frontend/skills/agents/vault_keeper.md`) for each doc with anchors:

1. **Anchor-existence gate first** — confirm each anchor path still exists at the sibling repo's
   HEAD (`git cat-file -e HEAD:<path>`, or `--follow` for renames). A missing anchor is reported
   as **"anchor moved — re-point"**, never silently treated as fresh. This gate exists because an
   empty `git log` diff on a dead path is indistinguishable from "nothing changed" — checking
   existence first is what prevents that false-fresh read.
2. **If the anchor exists**, run `git log --oneline <verified_against>..HEAD -- <path>` in that
   sibling repo.
   - Empty → doc is still current. Accept without re-reading the code.
   - Non-empty → those commits are what changed. Read the diff, update the doc if behavior
     (not just formatting) changed, and bump `verified_against` to the new HEAD sha.
3. **If the sibling repo isn't present** (isolated checkout, vault cloned alone) → report
   **"cannot verify — repo not present"**, never treat absence as fresh.

**`verified_against` only ever moves in the same commit that edits the doc.** No bulk
"mark everything verified" pass — that would create false confidence indistinguishable from a
real review. Git history on the vault repo is the backstop that proves a verification actually
happened when it claims to.

## Code ↔ doc reference convention

Inline code comments should point at a **stable ID**, never a file path:

```java
// See ADR-0007
```
not
```java
// See Modules/cart.md → Cart Lines
```

Paths break the moment a doc moves; IDs don't. One token threaded across three places resolves
the whole trail with a single grep:

- Code comment: `ADR-0007`
- Commit trailer: `Refs ADR-0007`
- ADR filename: `ADR-0007-....md`

`grep -rn "ADR-0007"` across all repos + the vault finds every place that decision touches.

Only add a pointer at genuine decision seams — where a dev could unknowingly break a non-obvious
rule (cart key formula, addon validation mirroring, DTO drift rules). Not on every file — sparse
and load-bearing beats exhaustive and ignored.

## What never enters this vault

`keys/`, `.backend-access.local`, `*.keystore`, `*credentials*`, `.env*` — secrets live in their
own repo-local, gitignored locations. `08-Ops/` holds *references* to where they live, never the
values. The vault `.gitignore` is a backstop, not the only control — don't rely on it as the sole
check before committing.
