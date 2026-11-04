FROM alpine:3.24
RUN apk add --no-cache mariadb-client aws-cli gnupg tar gzip tzdata && adduser -D -u 1000 backup
COPY --chmod=755 backup.sh /usr/local/bin/backup.sh
USER backup
ENTRYPOINT ["/usr/local/bin/backup.sh"]
