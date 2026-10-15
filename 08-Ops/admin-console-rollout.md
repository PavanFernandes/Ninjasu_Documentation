---
id: ""
title: "Admin console rollout (separate admin login + subdomain)"
summary: "Exact steps to put the new admin login live: DNS, nginx, certificate, backend settings, merge order, first-login check, rollback. Matches backend PR #39, web PR #33."
type: how-to
status: ready
apps: [backend, web]
module: "ops"
anchors: []
verified_against: "backend feature/admin-access @ 592fa89; Ninjasu_Web feature/admin-subdomain @ 6216bc3"
updated: 2026-10-08
---

# Admin console rollout

Design and decisions: [admin-access-redesign.md](../07-Roadmap/admin-access-redesign.md). Do the steps in order.
**Never paste the admin password, the hash or the secrets into chat, docs or git.**

## 0. Before anything: find the admin user id and check who else has ADMIN

Run in the database (pgAdmin / Neon SQL editor):

```sql
SELECT id, phone, name, roles FROM users WHERE 'ADMIN' = ANY(roles);
```
- Your row's `id` is `PLATFORM_ADMIN_USER_IDS`. Anyone else listed will **lose** admin when this ships — confirm that is intended.
- Your phone number on that row must be able to receive SMS from the real provider.

## 1. DNS
Add an **A record** `admin.ninjasu.com` → `13.200.51.223` (the Elastic IP, same as `ninjasu.com` / `api.ninjasu.com`). Wait until `nslookup admin.ninjasu.com` returns that IP.

## 2. nginx + certificate (on the EC2 host)
`/etc/nginx/conf.d/ninjasu-admin.conf` (plain HTTP first, certbot adds TLS like it did for the other hosts):

```nginx
server {
    listen 80;
    server_name admin.ninjasu.com;

    location / {
        proxy_pass http://localhost:3010;   # the same Next.js container as ninjasu.com
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;        # the app picks admin vs main by this header — must stay $host
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```
```bash
sudo nginx -t && sudo systemctl reload nginx
sudo certbot --nginx -d admin.ninjasu.com
```
Check disk first (`df -h`, the host is 20 GB and has filled before — see reference_prod_ec2_disk_and_cert).

## 3. Backend settings (`/home/ec2-user/ninja.env`, used by `docker run --env-file`)
The file is `/home/ec2-user/ninja.env`. Settings are read only when the container is created: adding them is safe ahead of the merge, and they take effect on the next deploy (which recreates the container). `docker restart` does NOT reload them.
Values are in `C:\Users\Lenovo\ninjasu-admin-server-settings.txt` (outside every repo). Add, exactly as written (no quotes):
```
ADMIN_JWT_SECRET=...
PLATFORM_ADMIN_USER_IDS=<id from step 0>
PLATFORM_ADMIN_PASSWORD_HASH=$2a$12$...
```
Confirm these already exist (the backend now refuses to start without them):
```
APP_JWT_SECRET=<your private value>      # the old built-in default is removed
OTP_PHONE_PROVIDER=messagecentral        # admin login refuses 'dev'
```
Then **delete the settings file** and keep the admin password in your password manager.

## 4. Merge order
1. Mobile PR (Food-Ninja-Frontend #27) — independent, any time.
2. Backend PR #39 (mark ready) **and** web PR #33 together. The backend deploy takes about 2 minutes; the old admin pages stop working as soon as it is live.
3. Watch the backend deploy: `docker logs ninja --tail 80` should show `Configured 1 platform admin user id(s)` and no `PLATFORM_ADMIN_PASSWORD_HASH is missing` error. A 502 for ~30 s right after deploy is just the container starting.

## 5. First login check
1. Open `https://admin.ninjasu.com` → redirects to `/admin/login`.
2. Phone + admin password → an SMS code arrives → enter it → you land on the admin dashboard; shops/riders/zones load.
3. `https://ninjasu.com/admin` must return **404**.
4. Ordinary customer/shop login on `ninjasu.com` still works.
5. After both clients are live, remove stale ADMIN from the roles arrays:
   ```sql
   UPDATE users SET roles = array_remove(roles, 'ADMIN') WHERE 'ADMIN' = ANY(roles);
   ```

## Rollback
Redeploy the previous backend image and web build (revert the two merge commits). Nothing in the database changed, so no data rollback is needed. A backend that will not start usually means a missing setting: check `docker logs ninja --tail 80` for the property name.

## Changing the admin password later
Generate a new bcrypt hash (cost 12), replace `PLATFORM_ADMIN_PASSWORD_HASH` in `~/ninja.env`, then recreate the container (a plain `docker restart` does not reload `--env-file` changes; redeploy or `docker rm -f ninja` + the `docker run` from docker.md). There is deliberately no forgot-password flow.
