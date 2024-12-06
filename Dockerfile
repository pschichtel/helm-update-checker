FROM alpine:3.21

RUN apk add --update --no-cache bash yq jq grep helm

COPY --chmod=755 helm-update-check.sh /usr/local/bin/helm-update-check

