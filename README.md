# ownCloud Web Extensions Docker Images

[![Docker Pulls](https://img.shields.io/docker/pulls/owncloud/web-extensions.svg)](https://hub.docker.com/r/owncloud/web-extensions)
[![License: Apache-2.0](https://img.shields.io/github/license/owncloud-docker/web-extensions)](https://github.com/owncloud-docker/web-extensions/blob/main/LICENSE)

Docker images for [ownCloud Web Extensions](https://github.com/owncloud/web-extensions)
— a collection of community and supplementary extensions for the
[ownCloud Web](https://github.com/owncloud/web) frontend, deployable as standalone web
apps within [ownCloud Infinite Scale (oCIS)](https://github.com/owncloud/ocis). This
repo builds and publishes the images; the extensions' source lives in
[owncloud/web-extensions](https://github.com/owncloud/web-extensions).

## Quick Start

Each extension is published as its own image tag under the single
`owncloud/web-extensions` Docker Hub repository, e.g.:

```bash
docker run --rm -p 8080:8080 owncloud/web-extensions:cast-latest
```

The container serves the built extension under `/<extension>/` (e.g.
`/cast/manifest.json`). See
[owncloud/web-extensions](https://github.com/owncloud/web-extensions#readme) for the
full list of extensions and how to deploy them into an oCIS instance.

## Supported Tags

Each extension gets two tags per release: an immutable version and a rolling `latest`.

| Tag | Meaning |
|-----|---------|
| `<extension>-<version>` | Immutable build of that extension's tagged release (e.g. `cast-0.4.1`) |
| `<extension>-latest` | Most recent build of that extension |

```bash
docker pull owncloud/web-extensions:cast-latest
```

## Build Arguments

| ARG | Default | Purpose |
|-----|---------|---------|
| `GIT_REF` | *(required)* | `web-extensions` git tag to clone and build, e.g. `cast-v0.4.1` |
| `PACKAGE` | *(required)* | Short extension name matching `packages/web-app-<PACKAGE>`, e.g. `cast` |
| `VERSION` | `""` | Version string embedded in OCI labels |
| `REVISION` | `""` | Git SHA embedded in OCI labels |

## Building

The image is built entirely from source via a two-stage `Dockerfile.multiarch`:

**`builder`** — clones `web-extensions` at `${GIT_REF}` and builds one extension
(`pnpm --filter ./packages/web-app-${PACKAGE} build`).

**Runtime** — a minimal `nginxinc/nginx-unprivileged` (Alpine) image, serving the
built extension's `dist/` under `/<PACKAGE>/`.

```bash
docker buildx build -f Dockerfile.multiarch \
  --build-arg GIT_REF=cast-v0.4.1 --build-arg PACKAGE=cast \
  -t web-extensions:test .
```

## How new releases get built

CI polls `owncloud/web-extensions` for tags matching `<extension>-v<version>`, keeps
only the newest version per extension, and builds/publishes whichever of those aren't
already on Docker Hub yet. See [`AGENTS.md`](AGENTS.md) for details.
