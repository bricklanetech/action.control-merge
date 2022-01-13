FROM alpine:latest

RUN apk add --no-cache \
    bash \
    git

ADD entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
