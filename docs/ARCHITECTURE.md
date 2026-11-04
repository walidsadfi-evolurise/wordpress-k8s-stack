# Architecture

```
                   ┌─────────────────────────── namespace: wordpress (PSS restricted) ──────────────────────────┐
 Internet ──TLS──► │ ingress-nginx ──► Service wordpress ──► Pod × N (HPA 2–8 / 3–12)                          │
                   │                                         ├─ nginx (unprivileged)  static + FastCGI cache   │
                   │                                         ├─ php-fpm (WordPress code baked in the image)   │
                   │                                         └─ nginx-exporter → Prometheus                   │
                   │                                                │          │                                │
                   │                 PVC wp-uploads (RWX) ◄─────────┘          ├──► redis (object cache, sessions)
                   │                                                           └──► mariadb (StatefulSet) or managed DB
                   │ CronJob wp-cron (every 5 min, wp-cli)      CronJob backup (nightly → S3, gpg)            │
                   │ NetworkPolicies: default deny; ingress-nginx→web:8080; web→db:3306, redis:6379, egress 443│
                   └───────────────────────────────────────────────────────────────────────────────────────────┘
```

## Decisions

| Decision | Why |
|---|---|
| **Code in the image, uploads on a volume** | Pods become replaceable: scale out, roll back, rebuild a node — nothing is lost. `DISALLOW_FILE_MODS` makes "install plugin from wp-admin" impossible in prod, so changes go through git and CI. |
| **nginx + php-fpm in one pod** | FastCGI over localhost, one Service, one scaling unit. The init container copies the code once so nginx serves static files directly. |
| **FastCGI cache in nginx, not a plugin** | Cached pages never touch PHP. Logged-in users, carts, checkout, REST and anything with a query string bypass it. `X-Cache` tells you what happened. |
| **Redis without persistence** | It is a cache. Persisting it buys nothing and costs IO. |
| **Kustomize, not Helm** | A WordPress stack has few knobs; what varies between environments is better expressed as patches than as 300 `values.yaml` keys. Rendered YAML is diffable and reviewable in a PR, and GitOps tools consume it as is. |
| **In-cluster MariaDB is optional** | Fine for small shops. For anything that matters, a managed database with PITR beats operating MariaDB yourself — the prod overlay shows how to drop the StatefulSet. |
| **Secrets from an external store** | `secretGenerator` literals only in `dev`. Prod uses External Secrets Operator; SealedSecrets or SOPS work the same way. |
| **Default-deny NetworkPolicies** | WordPress pods talk to the DB, Redis and the internet on 443. Nothing else. A compromised plugin can't scan the cluster. |
| **Restricted Pod Security** | Non-root, read-only root filesystem, no capabilities, seccomp. Enforced by the namespace label, not by hoping. |
| **WP-Cron as a CronJob** | Visitors never pay for cron; failures show up as failed Jobs, not slow pages. |

## Capacity notes

- php-fpm `pm.max_children = 20` at 256 MB memory limit ⇒ ~ 20 concurrent PHP requests per pod. With the FastCGI cache taking 80–95 % of anonymous traffic, two pods carry a mid-size shop comfortably; the HPA adds pods on CPU.
- MariaDB `innodb_buffer_pool_size` should be ~ 60 % of the container's memory limit; adjust both together.
- Uploads need **ReadWriteMany** for N > 1. EFS, CephFS, Longhorn RWX, OVH/Scaleway NFS, or offload media to S3 with a plugin and drop the PVC.

## Observability

- nginx exporter on `:9113` (requests, connections, cache status via logs).
- php-fpm `/status` and `/ping` on the FastCGI socket (used by the probes; expose with a php-fpm exporter if you want pool metrics).
- `/wp-json/health/v1/ready` checks DB and object cache from inside WordPress.
