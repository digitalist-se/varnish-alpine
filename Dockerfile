FROM alpine:3
LABEL maintainer="mikke.schiren™digitalist.se"
ENV VARNISH_VERSION=7.1.1-r0 \
    VARNISH_PORT=80 \
    VARNISHD_PARAMS='-p default_ttl=3600 -p default_grace=3600' \
    CACHE_SIZE=128m \
    SECRET_FILE=/etc/varnish/secret \
    VCL_CONFIG=/etc/varnish/default.vcl

RUN apk add --update git varnish=$VARNISH_VERSION && rm -rf /var/cache/apk/*
RUN git clone https://github.com/chrislim2888/IP2Location-C-Library/ ;\
    apk add build-base automake autoconf libtool ;\
    cd IP2Location-C-Library && autoreconf -i -v --force; \
    ./configure ;\
    make && make install ;\
    apk add --update python3 py3-docutils varnish-dev varnish-libs && rm -rf /var/cache/apk/* ;\
    git clone https://github.com/digitalist-se/IP2Location-Varnish.git /tmp/IP2Location-Varnish ;\
    cd /tmp/IP2Location-Varnish ;\
    ./autogen.sh ;\
    ./configure ;\
    make ;\
    make install ;\
    mkdir -p /usr/share/locationdb ;\
    apk del build-base automake autoconf libtool git

#COPY files/COUNTRY.BIN /usr/share/locationdb/COUNTRY.BIN

EXPOSE $VARNISH_PORT

COPY default.vcl /etc/varnish/default.vcl
COPY dummysecret /etc/varnish/secret
COPY entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
