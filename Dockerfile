FROM alpine:3.12

ENV ARGS=
ARG NETPERF_VERSION=2.7.0

WORKDIR /tmp
RUN apk --update add wget build-base bash && \
    wget https://github.com/HewlettPackard/netperf/archive/netperf-${NETPERF_VERSION}.tar.gz && \
    tar zxf netperf-${NETPERF_VERSION}.tar.gz && \
    cd netperf-netperf-${NETPERF_VERSION} && \
    ./configure && \
    make && \
    cp /tmp/netperf-netperf-${NETPERF_VERSION}/src/netserver /usr/local/bin/ && \
    cp /tmp/netperf-netperf-${NETPERF_VERSION}/src/netperf /usr/local/bin/ && \
    cd .. && \
    rm -rf netperf-* && \
    apk del wget build-base && \
    apk add iputils && \
    rm -vrf /var/cache/apk/*

WORKDIR /app
COPY betterspeedtest.sh /app/betterspeedtest
RUN chmod +x /app/betterspeedtest

CMD /app/betterspeedtest $ARGS
