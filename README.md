# jenkins-controller

A modified Jenkins package with plugins pre-installed.

## Building and publishing images

The repository is configured with a GitHub Actions workflow that builds and
publishes a multi-architecture container image to GHCR. Create and push a tag to
trigger the workflow. The resulting image supports both `linux/amd64` and
`linux/arm64` platforms so it can run on x86 and ARM Swarm nodes.

If you prefer to build locally, use Docker Buildx to produce a multi-arch image:

```bash
# Build and push multi-architecture image
# (replace ghcr.io/OWNER/jenkins-controller with your registry reference)
docker buildx build --platform linux/amd64,linux/arm64 \
  -t ghcr.io/OWNER/jenkins-controller:TAG \
  --push .
```

This ensures the image manifest advertises both architectures, preventing the
`unsupported platform` error when deploying to heterogeneous clusters.
