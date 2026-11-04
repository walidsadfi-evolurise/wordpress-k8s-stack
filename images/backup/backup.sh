#!/bin/sh
# Logical DB dump + uploads tarball, each gpg-encrypted (AES-256, symmetric),
# checksummed, uploaded to S3-compatible storage, with server-side retention.
# Runs as a Kubernetes CronJob with a read-only mount of the uploads PVC.
set -eu

: "${WORDPRESS_DB_HOST:=${DB_HOST:-mariadb}}"
: "${WORDPRESS_DB_NAME:?}" "${WORDPRESS_DB_USER:?}" "${WORDPRESS_DB_PASSWORD:?}"
: "${S3_BUCKET:?}" "${GPG_PASSPHRASE:?}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
WORK="/work/${STAMP}"
mkdir -p "${WORK}"
ENDPOINT_ARG=""
[ -n "${S3_ENDPOINT:-}" ] && ENDPOINT_ARG="--endpoint-url ${S3_ENDPOINT}"

echo "backup: start ${STAMP} (db ${WORDPRESS_DB_HOST}/${WORDPRESS_DB_NAME})"

mariadb-dump --host="${WORDPRESS_DB_HOST}" --user="${WORDPRESS_DB_USER}" --password="${WORDPRESS_DB_PASSWORD}" \
  --single-transaction --quick --routines --triggers --no-tablespaces "${WORDPRESS_DB_NAME}" \
  | gzip -6 \
  | gpg --batch --yes --symmetric --cipher-algo AES256 --passphrase "${GPG_PASSPHRASE}" -o "${WORK}/db.sql.gz.gpg"

tar -C /src -czf - uploads \
  | gpg --batch --yes --symmetric --cipher-algo AES256 --passphrase "${GPG_PASSPHRASE}" -o "${WORK}/uploads.tar.gz.gpg"

( cd "${WORK}" && sha256sum ./* > SHA256SUMS )
du -sh "${WORK}" | sed 's/^/backup: size /'

# shellcheck disable=SC2086
aws ${ENDPOINT_ARG} s3 cp "${WORK}" "s3://${S3_BUCKET}/${STAMP}/" --recursive --only-show-errors
echo "backup: uploaded to s3://${S3_BUCKET}/${STAMP}/"

# Retention: delete prefixes older than RETENTION_DAYS (prefix names are UTC timestamps).
CUTOFF="$(date -u -d "-${RETENTION_DAYS} days" +%Y%m%dT%H%M%SZ 2>/dev/null || date -u -v-"${RETENTION_DAYS}"d +%Y%m%dT%H%M%SZ)"
# shellcheck disable=SC2086
aws ${ENDPOINT_ARG} s3 ls "s3://${S3_BUCKET}/" | awk '{print $2}' | tr -d / | while read -r prefix; do
  # timestamps sort lexicographically; expr returns 1 when prefix < cutoff
  if [ -n "${prefix}" ] && [ "$(expr "${prefix}" \< "${CUTOFF}")" = 1 ]; then
    # shellcheck disable=SC2086
    aws ${ENDPOINT_ARG} s3 rm "s3://${S3_BUCKET}/${prefix}/" --recursive --only-show-errors
    echo "backup: pruned ${prefix}"
  fi
done

rm -rf "${WORK}"
echo "backup: done ${STAMP}"
