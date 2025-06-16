FROM public.ecr.aws/docker/library/golang:1.24.2-alpine AS build

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY . .

RUN go install github.com/pressly/goose/v3/cmd/goose@latest

RUN go build -o main .

FROM alpine:latest

ENV DOCKERIZE_VERSION=v0.9.3

RUN apk update --no-cache \
    && apk add --no-cache wget openssl \
    && wget -O - https://github.com/jwilder/dockerize/releases/download/$DOCKERIZE_VERSION/dockerize-alpine-linux-amd64-$DOCKERIZE_VERSION.tar.gz | tar xzf - -C /usr/local/bin \
    && apk del wget

WORKDIR /app

COPY --from=build /app/main .
COPY --from=build /go/bin/goose /usr/local/bin/goose
COPY migrations ./migrations
COPY static ./static
COPY templates ./templates

EXPOSE 8080
