# wordpress-k8s-stack

**Production WordPress / WooCommerce on Kubernetes: immutable code image, nginx FastCGI cache, Redis, autoscaling, default-deny networking, restricted Pod Security, encrypted backups — validated and deployed on a kind cluster in CI.**

[![CI](https://github.com/walidsadfi-evolurise/wordpress-k8s-stack/actions/workflows/ci.yml/badge.svg)](https://github.com/walidsadfi-evolurise/wordpress-k8s-stack/actions/workflows/ci.yml)
![Kubernetes 1.29+](https://img.shields.io/badge/kubernetes-1.29%2B-326ce5)
![License MIT](https://img.shields.io/badge/license-MIT-green)

*[Version française plus bas](#version-française)*

The Kubernetes sibling of [docker-wordpress-prod](https://github.com/walidsadfi-evolurise/docker-wordpress-prod). Same nginx cache rules, same PHP tuning, same backup format — for teams that already run a cluster and want WordPress to behave like the rest of their workloads: stateless pods, rolling updates, HPA, PDB, NetworkPolicies, secrets from a vault.

```
base/            everything, environment-agnostic (Kustomize)
overlays/dev     1 replica, kind-friendly storage, throwaway secrets, http://wordpress.localtest.me
overlays/prod    3+ replicas, zone spread, RWX uploads, cert-manager TLS, ExternalSecrets, pinned images
images/php       wordpress:fpm-alpine + redis ext + wp-cli + code baked in, non-root
images/backup    nightly dump + uploads → gpg → S3, retention
hack/            kind-up.sh · smoke.sh · wp.sh · validate.py
docs/            ARCHITECTURE.md · RESTORE.md
```

## What you get

| | |
|---|---|
| **Immutable releases** | WordPress core, plugins and themes live in the image. `DISALLOW_FILE_MODS` in prod. Deploy = new tag. Roll back = old tag. |
| **Fast by default** | nginx FastCGI cache with WooCommerce-aware bypass (cart, checkout, account, logged-in, REST, query strings), gzip, 30-day static assets, OPcache + JIT, Redis object cache and PHP sessions. |
| **Scales** | HPA on CPU (2→8 dev-sized, 3→12 prod), topology spread across nodes and zones, PDB, zero-downtime rolling updates with `maxUnavailable: 0`, graceful shutdown. |
| **Locked down** | Namespace enforces Pod Security *restricted*. Every container: non-root, read-only root FS, no capabilities, seccomp. Default-deny NetworkPolicies; the app can only reach its DB, Redis and the internet on 443. Login rate-limited, xmlrpc and config files blocked, no version headers. |
| **Operable** | Real cron as a CronJob, probes that check the actual app (`/wp-json/health/v1/ready` → DB + object cache), nginx metrics for Prometheus, `hack/wp.sh` for WP-CLI, a written and tested restore procedure. |
| **Backed up** | Nightly logical dump + uploads tarball, AES-256 encrypted, checksummed, pushed to any S3, pruned by retention. |
| **Proven in CI** | Manifests are rendered and validated strictly with kubeconform, policy-checked (pinned tags, resources, non-root), then **deployed on a kind cluster** where WordPress is installed and a smoke test asserts cache HITs, bypasses, rate limiting and headers. |

## Quick start

```bash
# local cluster with ingress, dev overlay, WordPress installed (kind + kubectl + docker)
hack/kind-up.sh
open http://wordpress.localtest.me        # admin / admin
hack/smoke.sh
```

```text
== nginx health
== app readiness
== home page
== fastcgi cache warms up
== query strings bypass
== login rate-limited
== rest api not cached
== security headers
== no php version leak
== blocked files
all good
```

### Production

1. Build and push `images/php` with your plugins/themes added to the Dockerfile; tag it.
2. Create the secrets in your store (`wordpress/prod/db`, `salts`, `mariadb-root`, `backup-s3`) — see `overlays/prod/externalsecrets.yaml`.
3. Set the domain in `overlays/prod/kustomization.yaml` and `patch-prod.yaml`, the RWX storage class, and pin the image tag (`kustomize edit set image … :1.2.3` from CI).
4. `kubectl diff -k overlays/prod` → review → `kubectl apply -k overlays/prod`, or point Argo CD / Flux at the overlay.
5. Run a restore drill (`docs/RESTORE.md`) before you need one.

Using a managed database? Uncomment the `$patch: delete` block in the prod overlay and point `WORDPRESS_DB_HOST` at it.

## Validate without a cluster

```bash
make lint          # yamllint + shellcheck
make validate      # kubeconform (strict) if installed, else hack/validate.py against the Kubernetes OpenAPI spec
```

`hack/validate.py` resolves each manifest's `apiVersion/kind` to its OpenAPI definition and validates with unknown fields forbidden — the same guarantee kubeconform gives, in 80 lines of Python, for environments where you can't install binaries.

## Design notes

Short version in the table above; the reasoning (why Kustomize over Helm here, why code-in-image, why Redis isn't persisted, why the DB is optional) is in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Roadmap

- [ ] Media offload to S3 (drop the RWX requirement)
- [ ] php-fpm exporter sidecar + Grafana dashboard
- [ ] Argo CD `Application` example with image updater
- [ ] Blue/green via a second Deployment + Service selector switch for risky WooCommerce upgrades

## License

MIT — see [LICENSE](LICENSE). Built by [Walid Sadfi](https://www.malt.fr/profile/walidsadfi), Forward Deployed Engineer · agents IA & WooCommerce.

---

## Version française

**WordPress / WooCommerce en production sur Kubernetes : image de code immuable, cache FastCGI nginx, Redis, autoscaling, réseau en refus par défaut, Pod Security restricted, sauvegardes chiffrées — validé et déployé sur un cluster kind à chaque CI.**

Le pendant Kubernetes de [docker-wordpress-prod](https://github.com/walidsadfi-evolurise/docker-wordpress-prod), pour les équipes qui ont déjà un cluster et veulent que WordPress se comporte comme le reste de leurs workloads.

- **Releases immuables** : core, plugins et thèmes dans l'image ; `DISALLOW_FILE_MODS` en prod ; déployer = nouveau tag, revenir en arrière = ancien tag.
- **Rapide** : cache FastCGI avec contournement WooCommerce (panier, checkout, compte, connecté, REST, query strings), OPcache + JIT, Redis pour le cache objet et les sessions.
- **Scalable** : HPA, répartition par nœud et par zone, PDB, rolling update sans interruption.
- **Verrouillé** : Pod Security *restricted* imposé par le namespace, conteneurs non-root en lecture seule, NetworkPolicies en refus par défaut, login limité en débit, xmlrpc bloqué.
- **Exploitable** : cron réel en CronJob, sondes qui testent l'application (BDD + cache objet), métriques nginx, WP-CLI via `hack/wp.sh`, procédure de restauration écrite et testée.
- **Prouvé en CI** : rendu + validation stricte (kubeconform), contrôles de politique, puis déploiement sur kind avec installation de WordPress et tests de fumée (HIT de cache, bypass, 429 sur le login, en-têtes).

```bash
hack/kind-up.sh && hack/smoke.sh
```

Vous avez un cluster et un WooCommerce qui tourne encore sur un serveur « historique » ? [Parlons-en sur Malt](https://www.malt.fr/profile/walidsadfi) : migration mesurée, sans coupure, avec un point de contrôle à 30 jours.
