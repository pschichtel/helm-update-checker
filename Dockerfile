FROM alpine:3.18

RUN apk add --update --no-cache bash curl yq jq

COPY --chmod=755 helm-update-check.sh /usr/local/bin/helm-update-check

