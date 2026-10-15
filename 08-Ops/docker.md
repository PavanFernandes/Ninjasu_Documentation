---
id: ""
title: "Docker Setup (Backend on EC2)"
summary: "Operational runbook for the backend Docker container on EC2 — checking status/logs, start/stop/restart, Elastic IP behavior on reboot, and the redeploy command sequence."
type: how-to
status: active
apps: [backend, customer, admin, rider]
module: "ops"
anchors:
  - { repo: backend, path: "Dockerfile" }
verified_against: "ff5ade334891238d16b8010e372fdbbc502c193e"
updated: 2026-07-11
---

# Docker Setup (Backend on EC2)

Operational notes for the backend container (`ninja`) running on the EC2 instance behind `api.ninjasu.com`.

## Check status & logs

```bash
# Is the container running?
docker ps

# Live logs (Ctrl+C to exit)
docker logs -f ninja

# Last 50 lines
docker logs ninja --tail 50
```

## Stop / start the container

```bash
# Stop
docker stop ninja

# Start again (same container, no need to re-run)
docker start ninja

# Restart
docker restart ninja
```

## If the EC2 instance stops/reboots

The container will auto-start because of `--restart unless-stopped` — you don't need to do anything. Docker starts it automatically on boot.

## If the IP changes (instance stopped and restarted)

The Elastic IP (`13.200.51.223`) never changes — that's the whole point of allocating it. As long as it stays associated with the instance, `api.ninjasu.com` will always resolve correctly. IP changes only happen if you:

- **Dissociate the Elastic IP** — don't do this.
- **Terminate the instance and create a new one** — then reassociate the Elastic IP to the new instance and you're fine.

So in normal operation (stop/start the instance, reboot), nothing changes. The Elastic IP stays, the container auto-restarts, your domain keeps working.

## Redeploy after a code change

```bash
cd ~/Food-Ninja-Java-Backend
git pull
docker build -t ninja-backend .
docker stop ninja && docker rm ninja
docker run -d --name ninja \
  --restart unless-stopped \
  -p 8080:8080 \
  --env-file ~/ninja.env \
  -v ~/firebase-service-account.json:/secrets/firebase-service-account.json:ro \
  ninja-backend
```
