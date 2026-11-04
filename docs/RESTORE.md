# Restore procedure

Tested on every release: a backup you have never restored is a hope, not a backup.

## 1. Pick the backup

```bash
aws --endpoint-url "$S3_ENDPOINT" s3 ls "s3://$S3_BUCKET/"          # prefixes are UTC timestamps
aws --endpoint-url "$S3_ENDPOINT" s3 cp "s3://$S3_BUCKET/20261104T031500Z/" ./restore --recursive
cd restore && sha256sum -c SHA256SUMS
```

## 2. Database

```bash
gpg --batch --passphrase "$GPG_PASSPHRASE" -d db.sql.gz.gpg | gunzip > db.sql
kubectl -n wordpress scale deployment/wordpress --replicas=0      # stop writers
kubectl -n wordpress exec -i mariadb-0 -- sh -c 'mariadb -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" "$MARIADB_DATABASE"' < db.sql
```

Managed database: use its native import or `mariadb -h <host> …` from a bastion.

## 3. Uploads

```bash
gpg --batch --passphrase "$GPG_PASSPHRASE" -d uploads.tar.gz.gpg > uploads.tar.gz
POD=$(kubectl -n wordpress get pod -l app.kubernetes.io/name=wp-cron -o name | head -1)   # or start a one-off pod mounting wp-uploads
kubectl -n wordpress run restore --rm -it --restart=Never --image=alpine:3.20 \
  --overrides='{"spec":{"securityContext":{"runAsUser":82,"runAsGroup":82,"fsGroup":82,"runAsNonRoot":true,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"r","image":"alpine:3.20","command":["sleep","3600"],"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}},"volumeMounts":[{"name":"u","mountPath":"/uploads"}]}],"volumes":[{"name":"u","persistentVolumeClaim":{"claimName":"wp-uploads"}}]}}' &
kubectl -n wordpress cp uploads.tar.gz restore:/tmp/
kubectl -n wordpress exec restore -- sh -c 'cd /uploads && tar -xzf /tmp/uploads.tar.gz --strip-components=1'
```

## 4. Back online

```bash
kubectl -n wordpress scale deployment/wordpress --replicas=2
hack/wp.sh cache flush && hack/wp.sh redis flush || true
hack/smoke.sh
```

## Drill

Quarterly: restore into a scratch namespace (`kustomize edit set namespace wordpress-drill`) and run the smoke test against it. Time it. Write the number down.
