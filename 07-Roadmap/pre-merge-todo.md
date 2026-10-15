---
id: ""
title: "Pre-merge TODO — admin access, stock fix, mobile admin removal"
summary: "Ordered checklist of what is left before merging backend PR #38 (stock fix), #39 (admin login), web PR #33 (admin subdomain) and mobile PR #27, plus the other open items. Owner marked per line."
type: how-to
status: active
apps: [backend, web, customer]
module: "ops"
anchors: []
verified_against: "PRs as of 2026-10-09"
updated: 2026-10-09
---

# Pre-merge TODO (2026-10-09)

Owner: **S** = Samivan, **C** = Claude. Runbook details: [admin-console-rollout.md](../08-Ops/admin-console-rollout.md).

## A. Do first (nothing deploys)
- [x] **S** Neon SQL Editor: create the `claude_readonly` login (SQL from chat), same password as in `C:\Users\Lenovo\.claude.json`.
- [x] **S** New Claude Code session in the `Food Ninja` folder; `/mcp` shows `food-ninja-db` connected.
- [x] **C** Run the 4 read-only checks: ADMIN holders + your user id; `deliveries.created_by_staff_id` nullable; duplicate open stock rows; role counts.
- [x] **S** Decide the admin password string: the hash was made from `copyNinjasu#3443` (with "copy"). If you meant `Ninjasu#3443`, tell C to regenerate.
- [x] **S** Put your user id into `PLATFORM_ADMIN_USER_IDS` in `C:\Users\Lenovo\ninjasu-admin-server-settings.txt`.

## B. Stock fix, backend PR #38 (deploys on merge). Merge this first, alone.
- [ ] **C/S** Optional smoke test on a Neon *branch*: place a tracked order, cancel it, `sold_qty` returns on the same ledger row.
- [ ] **S** Merge #38; watch the deploy (`docker logs ninja --tail 80`; a 502 for ~30 s is normal).
- [ ] **C** Check `order_lines.stock_ledger_id` exists (SQL 3).

## C. Server prep (before #39 and #33)
- [x] DNS `admin.ninjasu.com` → `13.200.51.223`, DNS only (verified).
- [x] **S** EC2: `df -h` (disk has filled before), then create `/etc/nginx/conf.d/ninjasu-admin.conf`, `sudo nginx -t && sudo systemctl reload nginx`, `sudo certbot --nginx -d admin.ninjasu.com`.
- [x] **S** Confirm prod has `APP_JWT_SECRET` (own value) and `OTP_PHONE_PROVIDER=messagecentral`. Names only, no values shown:
  `grep -E '^(APP_JWT_SECRET|OTP_PHONE_PROVIDER)=' ~/ninja.env | sed 's/=.*/=<set>/'`
- [x] **S** Add to `~/ninja.env`, exactly as written, no quotes: `ADMIN_JWT_SECRET`, `PLATFORM_ADMIN_USER_IDS`, `PLATFORM_ADMIN_PASSWORD_HASH`.
- [ ] **S** Change the Neon owner password (it was shown in chat) **in the same edit** of `~/ninja.env`, so there is one recreate, not two: update the datasource password in `~/ninja.env`, reset it in Neon, then **recreate** the container (`docker restart` does NOT reload env files): `sudo -u ec2-user bash -c "cd ~ && docker rm -f ninja && docker run -d --name ninja --restart unless-stopped -p 8080:8080 --env-file ~/ninja.env -v ~/firebase-service-account.json:/secrets/firebase-service-account.json:ro ninja-backend"`.
- [ ] **S** Delete `C:\Users\Lenovo\ninjasu-admin-server-settings.txt`; keep the admin password in a password manager.

## D. Merge admin (production)
- [ ] **S** Merge mobile PR #27 (independent; any time). Check: shop-owner login lands on shop tabs, customer login unchanged.
- [ ] **S** Mark backend #39 *Ready for review*; merge **#39 and web #33 together**.
- [ ] **C/S** Logs show `Configured 1 platform admin user id(s)` and no `PLATFORM_ADMIN_PASSWORD_HASH is missing`.

## E. After merge
- [ ] **S** `https://admin.ninjasu.com` → login (password, then SMS code) → dashboard loads shops/riders/zones.
- [ ] **S** `https://ninjasu.com/admin` returns 404; normal shop login on `ninjasu.com` still works.
- [ ] **S** `RESET ROLE; UPDATE users SET roles = array_remove(roles, 'ADMIN') WHERE 'ADMIN' = ANY(roles);` (run last).
- [ ] **S** Later: replace the admin password with one never typed in chat (new hash, replace setting, restart).
- [ ] **C** Move the admin settings runbook status to done; remove `claude_readonly` access if no longer needed.

## F. Other open items (not blocking the above)
- [ ] Rider app: phone test of offer → accept → pickup → complete (PR #3 fixes).
- [ ] Mobile POS permissions (PR #26): phone test as Owner, Cashier, new-shop Staff, Chef (checklist `pos-mobile-permissions-device-test.md`).
- [ ] Online payment (Razorpay): adversarial re-review before switching on (Schedule needs prepaid).
- [ ] Schedule Phase 1 decisions D1–D4, D6 still need your OK ([schedule-design-review.md](schedule-design-review.md)).
- [ ] Later: add `UNIQUE ... WHERE is_open` on `item_stock_ledger` once the duplicate check is clean.
