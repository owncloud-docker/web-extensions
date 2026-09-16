# AGENTS.md — web-extensions

## Repository Overview

This repository builds the official **ownCloud Web Extensions** Docker images
(`owncloud/web-extensions` on Docker Hub — one repo, one image tag per extension). It
does not contain the extensions' source code — it builds them **from source** by
cloning [`owncloud/web-extensions`](https://github.com/owncloud/web-extensions) at a
release tag and running that one extension's `pnpm build`. Images are multi-architecture
and built via GitHub Actions.

`owncloud/web-extensions` is a pnpm monorepo of independently-versioned extensions
(`packages/web-app-*`) for the ownCloud Web frontend. Its own
`.github/workflows/release.yml` builds and pushes images too, but that workflow is
broken (no `DOCKERHUB_*` secrets configured, and it uses actions —
`docker/metadata-action`, `docker/build-push-action`, `softprops/action-gh-release` —
that aren't on the OSPO allowlist). This repo takes over the Docker-publishing half of
that job; the app repo's GitHub-Release (zip + checksums) job is unaffected.

- **Classification:** Docker image build (from source)
- **Activity Status:** Active
- **License:** Apache-2.0
- **Language:** Dockerfile, Shell

## Architecture & Key Paths

- `Dockerfile.multiarch` — two-stage build (build context is the repo root):
  - **builder** (`node:24-alpine`) — clones `owncloud/web-extensions` at `${GIT_REF}`
    (a release tag, e.g. `cast-v0.4.1`) and builds one package with
    `pnpm --filter ./packages/web-app-${PACKAGE} build`.
  - **runtime** (`nginxinc/nginx-unprivileged:alpine` — chosen over the app repo's own
    `docker/Dockerfile` base, `owncloudops/nginx`, because that image has never
    published an arm64 variant, which would break the arm64 leg of the reusable
    `owncloud-docker/ubuntu` CI workflows) — copies that package's `dist/` to
    `/usr/share/nginx/html/${PACKAGE}`, runs as the non-root `nginx` user (uid 101,
    the base image's own default).
- `.github/workflows/main.yml` — **active** CI: polls for and builds pending releases
- `scripts/resolve-pending-releases.sh` — the polling/diff logic `main.yml`'s
  `prepare` job calls; extracted to its own file (rather than embedded in the
  workflow YAML, as the sibling repos do for their much simpler resolve steps)
  because it's real logic worth linting and running directly, not just YAML text
- `scripts/ignored-releases.txt` — manually-curated list of upstream release tags
  to never build (see the file's own header for why this is manual, not inferred)
- `.github/workflows/lint-pr-title.yml` — Conventional-Commit PR-title enforcement
- `.github/dependabot.yml` — weekly GitHub Actions and Docker base-image dependency updates
- `.github/CODEOWNERS` — review ownership
- `.editorconfig` — formatting rules (2-space indent, LF, trailing newline)
- `.trivyignore` — accepted-CVE exclusions for the Trivy scan
- `LICENSE` — Apache-2.0

There is **no `CHANGELOG.md`** in this repository.

## Build & CI

CI (`main.yml`) has no upstream tag to react to directly — GitHub Actions can't trigger
off another repo's tag push — so a `prepare` job runs `scripts/resolve-pending-releases.sh`
instead, which:

1. `git ls-remote --tags` the upstream repo, parse tags matching `<package>-v<version>`,
  dropping anything listed in `scripts/ignored-releases.txt`.
2. Diff the rest against Docker Hub's existing tags for `owncloud/web-extensions`
  (paginated). **Every** non-ignored missing release gets built — there is
  deliberately no "keep only the highest version per package" reduction here.
  An earlier version of this script had one, and it silently dropped legitimate
  releases: two patch releases landing in the same polling window would only
  build the higher one, and it would stay unbuilt forever (the next run's dedup
  would make the same choice again). Comparing version numbers can't reliably
  tell "abandoned old release" apart from "patch to an older, still-maintained
  line" either — there's no total order across concurrently-maintained lines.
  `ignored-releases.txt` handles the one actual need (don't rebuild bootstrap-era
  abandoned tags forever) as a manual, explicit, one-time decision instead.
3. Whatever's missing becomes the `build` job's matrix — one leg per
  `{package, version, ref, sha}`. Empty matrix short-circuits the `build` job entirely.

`build` calls the reusable `docker-build-native.yml` workflow (from
[`owncloud-docker/ubuntu`](https://github.com/owncloud-docker/ubuntu)) per matrix leg:
tags `<package>-<version>` and `<package>-latest`, Trivy-scanned (`.trivyignore`,
`exit-code: 1`), smoke-tested by curling
`http://localhost:8080/<package>/manifest.json` (every extension's Vite `public/`
directory ships a `manifest.json`, copied verbatim into `dist/` — a reliable,
version-agnostic smoke-test target with no per-extension special-casing needed).
Pushed to Docker Hub on non-PR events.

Schedule: every 6 hours (`0 */6 * * *`), plus `workflow_dispatch` and `pull_request`
(paths: `Dockerfile.multiarch`, `.github/workflows/main.yml`,
`scripts/resolve-pending-releases.sh`, `scripts/ignored-releases.txt`) for dry-run
validation.

To run the polling logic directly (e.g. to check what's currently pending):

```bash
scripts/resolve-pending-releases.sh
```

To build one extension locally:

```bash
docker buildx build -f Dockerfile.multiarch \
  --build-arg GIT_REF=cast-v0.4.1 --build-arg PACKAGE=cast \
  -t web-extensions:test .
```

The image exposes port `8080` and serves its extension under `/<PACKAGE>/`.

## Development Conventions

- **No CHANGELOG** — do not create one.
- Conventional-Commit PR titles, enforced by `lint-pr-title.yml`.
- `.editorconfig` governs formatting; `LICENSE` is exempt from the indent rules.
- GitHub Actions are pinned to full commit SHAs.
- Workflows declare a least-privilege `permissions:` block.
- Bug reports for the extensions themselves go upstream to
  [`owncloud/web-extensions`](https://github.com/owncloud/web-extensions); this repo
  tracks only the Docker packaging.

## OSPO Policy Constraints

### GitHub Actions
- **Only** use actions owned by `owncloud`, created by GitHub (`actions/*`),
  verified on the GitHub Marketplace, or verified by the ownCloud Maintainers.
- Pin all actions to their full commit SHA (not tags): `uses: actions/checkout@<SHA> # vX.Y.Z`.
- Never introduce actions from unverified third parties.

### Dependency Management
- Dependabot covers both GitHub Actions and Docker base-image updates for this
  repo (`.github/dependabot.yml`) — Renovate is not used here.
- Review and merge dependency PRs as part of regular maintenance. Base images in
  `Dockerfile.multiarch` must remain pinned as `tag@sha256:<digest>`; Dependabot
  updates the digest in place.

### Git Workflow
- **Rebase policy**: Always rebase; never create merge commits.
- **Signed commits**: All commits **must** be PGP/GPG signed (`git commit -S`).
- **DCO sign-off**: Every commit needs a `Signed-off-by` line (`git commit -s`).
- **Conventional Commits & Squash Merge**: PR titles must follow
  [Conventional Commits](https://www.conventionalcommits.org/); the PR title
  becomes the squash-merge commit message and is enforced by CI.

## Context for AI Agents

- This is a Docker-image build repo that compiles web-extensions from source — not
  the extensions' application codebase. Application changes belong upstream.
- One Docker Hub repo, many tags — one per extension per version, plus a rolling
  `<extension>-latest` per extension. There is no single "the" image.
- The polling `prepare` job is the only thing that decides what gets built; it always
  tracks the newest release per extension, never older ones.
- License is **Apache-2.0**, the OSPO's ecosystem-wide target; no relicensing needed.
