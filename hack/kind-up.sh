#!/usr/bin/env bash
# Local cluster with ingress-nginx, the dev overlay applied, and WordPress installed.
# Requires: kind, kubectl, docker. ~3 minutes on a laptop.
set -euo pipefail
CLUSTER="${CLUSTER:-wp}"
cd "$(dirname "$0")/.."

if ! kind get clusters | grep -qx "$CLUSTER"; then
  kind create cluster --name "$CLUSTER" --config hack/kind-config.yaml
fi

echo "== ingress-nginx"
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.12.1/deploy/static/provider/kind/deploy.yaml
kubectl -n ingress-nginx rollout status deployment/ingress-nginx-controller --timeout=180s

echo "== php image"
docker build -t ghcr.io/walidsadfi-evolurise/wordpress-k8s-php:dev images/php
kind load docker-image --name "$CLUSTER" ghcr.io/walidsadfi-evolurise/wordpress-k8s-php:dev

echo "== apply dev overlay"
kubectl apply -k overlays/dev
kubectl -n wordpress rollout status statefulset/mariadb --timeout=300s
kubectl -n wordpress rollout status deployment/redis --timeout=120s
kubectl -n wordpress rollout status deployment/wordpress --timeout=300s

echo "== install WordPress"
hack/wp.sh core is-installed 2>/dev/null || hack/wp.sh core install \
  --url=http://wordpress.localtest.me --title="Dev shop" \
  --admin_user=admin --admin_password=admin --admin_email=admin@example.com --skip-email
hack/wp.sh plugin activate redis-cache
hack/wp.sh redis enable

echo
echo "Open http://wordpress.localtest.me (admin / admin). Smoke test: hack/smoke.sh"
