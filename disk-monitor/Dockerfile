FROM alpine:3.20

RUN apk add --no-cache \
    curl \
    util-linux

ENTRYPOINT ["/scripts/disk-monitor.sh"]
