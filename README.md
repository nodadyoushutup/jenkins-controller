# jenkins-controller

A modified Jenkins package with plugins pre-installed.

## Running locally with Docker Compose

The Compose definition under `docker/docker-compose.yml` builds from the same
`docker/` directory that the CI workflow uses for its build context. When you
run `docker compose` it picks up the `docker/Dockerfile` along with the shared
`plugins.txt` and `export-agent-secret.groovy` files, ensuring identical
behaviour between local and published images.

```sh
docker compose -f docker/docker-compose.yml up --build
```

## Publishing the image

This repository uses GitHub Actions to publish a multi-architecture container
image to GitHub Container Registry. Create a tag (for example, `2.528`) and push
it to trigger the workflow. The workflow builds images for both `linux/amd64`
and `linux/arm64` and pushes them to `ghcr.io/<owner>/jenkins-controller` with
the tag name and `latest`.

If you need to publish manually, you can also run the workflow using the
"Run workflow" button in the Actions tab.
