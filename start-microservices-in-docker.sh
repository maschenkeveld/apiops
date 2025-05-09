#!/bin/bash

SERVICE=$1     # e.g., alice or bob
PORT=$2        # e.g., 9000 or 9001

IMAGE="nexus.pve-1.schenkeveld.io:8444/mesh-crawler:go-1.0.19"

sudo docker run -d \
  --rm \
  --name "$SERVICE" \
  -e PORT="$PORT" \
  -e NAME="$SERVICE" \
  -e HOSTNAME="localhost" \
  -e ZONE="dev" \
  -p "$PORT:$PORT" \
  "$IMAGE" > /dev/null

echo "Started $SERVICE on port $PORT"
