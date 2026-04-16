FROM alpine:3.20

RUN apk add --no-cache \
    smartmontools \
    nvme-cli \
    curl \
    jq \
    util-linux

ENTRYPOINT ["/scripts/disk-monitor.sh"]
