#!/usr/bin/env bash
# End-to-end checks against a running stack (dev overlay by default).
set -euo pipefail
BASE="${BASE:-http://wordpress.localtest.me}"
fail() { echo "FAIL: $*" >&2; exit 1; }

# The ingress controller can take a few seconds to pick up fresh endpoints: retry the first probe.
# Header checks use GET (-D -), not HEAD (-I): the cache key includes the method, so a HEAD never hits.
echo "== nginx health"
for _ in $(seq 1 30); do
  if curl -fsS "$BASE/nginx-health" 2>/dev/null | grep -qx ok; then break; fi
  sleep 2
done
curl -fsS "$BASE/nginx-health" | grep -qx ok || { curl -sSi "$BASE/nginx-health" | head -20; fail "nginx-health"; }
echo "== app readiness";           curl -fsS "$BASE/wp-json/health/v1/ready" | grep -q '"status":"ok"' || { curl -sS "$BASE/wp-json/health/v1/ready" | head -c 400; echo; fail "readiness (db / object cache)"; }
echo "== home page";               curl -fsS -o /dev/null -w '%{http_code}\n' "$BASE/" | grep -qx 200 || fail "home 200"
echo "== fastcgi cache warms up";  curl -fsS -o /dev/null "$BASE/"; curl -fsS -D - -o /dev/null "$BASE/" | grep -qi '^x-cache: HIT' || fail "X-Cache HIT on second request"
echo "== query strings bypass";    curl -fsS -D - -o /dev/null "$BASE/?s=probe" | grep -qi '^x-cache: BYPASS' || fail "search BYPASS"
echo "== login rate-limited";      for _ in 1 2 3 4 5 6 7 8; do curl -s -o /dev/null -w '%{http_code}\n' "$BASE/wp-login.php"; done | grep -qx 429 || fail "expected a 429 on burst login"
echo "== rest api not cached";     if curl -fsS -D - -o /dev/null "$BASE/wp-json/" | grep -qi 'x-cache'; then fail "REST must not carry X-Cache"; fi
echo "== security headers";        curl -fsS -D - -o /dev/null "$BASE/" | grep -qi '^x-content-type-options: nosniff' || fail "nosniff"
echo "== no php version leak";     if curl -fsS -D - -o /dev/null "$BASE/" | grep -qi '^x-powered-by'; then fail "X-Powered-By leaked"; fi
echo "== blocked files";           curl -s -o /dev/null -w '%{http_code}\n' "$BASE/xmlrpc.php" | grep -qx 404 || fail "xmlrpc should be 404"
echo "all good"
