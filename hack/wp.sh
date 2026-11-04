#!/usr/bin/env bash
# Run WP-CLI inside the first WordPress pod: hack/wp.sh plugin list
set -euo pipefail
POD="$(kubectl -n wordpress get pod -l app.kubernetes.io/name=wordpress -o jsonpath='{.items[0].metadata.name}')"
kubectl -n wordpress exec -i "$POD" -c php -- env HOME=/tmp WP_CLI_CACHE_DIR=/tmp/wp-cli-cache wp "$@"
