FROM rclone/rclone:1.68

RUN apk add --no-cache \
    docker-cli \
    curl \
    jq \
    rsync \
    gzip \
    tar

ENTRYPOINT ["/scripts/backup.sh"]
