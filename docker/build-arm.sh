#!/bin/bash
#
# Build ARM-compatible Docker image
#

echo "Building ARM Docker image..."

# Setup buildx if not exists
docker buildx create --name pibuilder --use || docker buildx use pibuilder

# Build for ARM platforms
docker buildx build \
    --platform linux/arm64,linux/arm/v7 \
    -t stabsstelle:arm \
    -f Dockerfile.pi \
    --push \
    .

echo "ARM image built and pushed!"
