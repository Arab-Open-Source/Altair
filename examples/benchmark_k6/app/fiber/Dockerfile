FROM golang:1.25-alpine AS build
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY main.go ./
RUN CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o /server .

FROM alpine:3.20
WORKDIR /app
COPY --from=build /server /usr/local/bin/server
EXPOSE 8080
CMD ["server"]