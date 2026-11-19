# NG 网关 · 控制面（Go）运行时镜像
FROM golang:1.22-alpine AS build
WORKDIR /src
COPY go.mod ./
RUN go mod download
COPY . .
RUN go build -o /ng-gatewayd ./cmd/ng-gatewayd

FROM alpine:3.19
RUN addgroup -S ngw && adduser -S ngw -G ngw
COPY --from=build /ng-gatewayd /usr/local/bin/ng-gatewayd
USER ngw
EXPOSE 8081
ENTRYPOINT ["ng-gatewayd"]