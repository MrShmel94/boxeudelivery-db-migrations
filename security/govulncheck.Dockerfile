FROM golang:1.27.1-alpine@sha256:8a5910f31396cd4d89662f56c68b3ae31d374308270a1c3bd96672ee5ed43414 AS build
ENV CGO_ENABLED=0 GOTOOLCHAIN=local
RUN GOBIN=/tools go install golang.org/x/vuln/cmd/govulncheck@v1.8.0 \
    && test "$(cat /go/pkg/mod/cache/download/golang.org/x/vuln/@v/v1.8.0.ziphash)" = 'h1:clG4qBU6zH5VKjti8n5j8BBuYzoSha392xXMkXS351U='

FROM alpine:3.23@sha256:85fe1e81d6758c208f3e1eed4338a1997e19d4be002d4dd32d3100c9a8c010a0
RUN apk upgrade --no-cache && apk add --no-cache ca-certificates
COPY --from=build --chmod=0555 /tools/govulncheck /usr/local/bin/govulncheck
COPY --from=build --chmod=0444 /go/pkg/mod/golang.org/x/vuln@v1.8.0/LICENSE /usr/share/licenses/govulncheck/LICENSE
ENV HOME=/tmp
USER 65532:65532
ENTRYPOINT ["govulncheck"]
HEALTHCHECK NONE
