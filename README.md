# jenkins-controller

A modified Jenkins package with plugins pre-installed.

## Publishing the image

This repository uses GitHub Actions to publish a multi-architecture container
image to GitHub Container Registry. Create a tag (for example, `2.528`) and push
it to trigger the workflow. The workflow builds images for both `linux/amd64`
and `linux/arm64` and pushes them to `ghcr.io/<owner>/jenkins-controller` with
the tag name and `latest`.

If you need to publish manually, you can also run the workflow using the
"Run workflow" button in the Actions tab.
