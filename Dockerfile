FROM alpine:3
LABEL maintainer="mikke.schiren™digitalist.se"
ENV VARNISH_VERSION=7.1.1-r0 \
    VARNISH_PORT=80 \
    VARNISHD_PARAMS='-p default_ttl=3600 -p default_grace=3600' \
    CACHE_SIZE=128m \
    SECRET_FILE=/etc/varnish/secret \
    VCL_CONFIG=/etc/varnish/default.vcl

RUN apk add --update varnish=$VARNISH_VERSION && rm -rf /var/cache/apk/*

EXPOSE $VARNISH_PORT

COPY default.vcl /etc/varnish/default.vcl
COPY dummysecret /etc/varnish/secret
COPY entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
