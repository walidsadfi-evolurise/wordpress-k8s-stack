# Changelog

## 0.1.0 — 2026-11-04

- Kustomize base: WordPress Deployment (nginx + php-fpm + exporter), HPA, PDB, Service, Ingress, Redis, MariaDB StatefulSet, wp-cron and backup CronJobs, default-deny NetworkPolicies, restricted Pod Security namespace.
- Overlays: dev (kind) and prod (zone spread, RWX storage, cert-manager, ExternalSecrets, pinned images).
- Images: PHP-FPM with code baked in and a readiness mu-plugin; backup image with gpg + S3 retention.
- CI: yamllint, shellcheck, kubeconform strict, policy checks, kind end-to-end with WordPress install and smoke tests, image publishing to ghcr.io.
- Docs: architecture decisions, restore procedure.
