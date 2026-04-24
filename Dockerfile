# Step 1: Build the Go app
FROM golang:1.25.5-alpine3.21 AS builder

# Set the Current Working Directory inside the container
WORKDIR /app

# Copy the Go Modules file
COPY go.mod go.sum ./

# Download all dependencies. Dependencies will be cached if the go.mod and go.sum are not changed
RUN go mod tidy

# Copy the entire local directory to the working directory inside the container
COPY . .

# Build the Go app
RUN go build -o main ./cmd/main.go

# Step 2: Create the final image
FROM alpine:latest

WORKDIR /root/

# Copy the Pre-built binary file from the builder stage
COPY --from=builder /app/main .

# Expose ports
# grpc
EXPOSE 5000
# http for user traffic
EXPOSE 8000
# http for metrics, pprof, health
EXPOSE 9000

## Command to run the executable
ENTRYPOINT ["./main"]
