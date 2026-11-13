---
name: release
description: Cut a Kiln Forever release, a signed v* tag that builds the addon and bridge tarball on GitHub. Use when asked to release, tag or publish Kiln Forever.
---

# Release Kiln Forever

Kiln Forever ships only as a GitHub release: `.github/workflows/release.yml` runs on a `v*` tag, checks the tag
against `bridge/package.json` and `addon/KilnForever/KilnForever.toc`, tars `addon`, `bridge`, `install.sh` and the
docs without tests, tools and types, and publishes the `## <version>` section of `CHANGELOG.md` as the notes. It has
no store upload and no `.pkgmeta`, so the headless smoke gate the store addons run (`headless-smoke` and
`release_check.py`) does not apply: its addon needs the bridge to show anything, and players install it through
`install.sh`.

1. Start from clean `main` at `origin/main`. Pick the version: patch for fixes, minor for features.
2. Rename `## [Unreleased]` in `CHANGELOG.md` to `## <version>`, with no brackets: the workflow's awk matches that
   exact line. Add a fresh empty `## [Unreleased]` above it.
3. Set the same version in `bridge/package.json` and in the TOC's
   `## Version:` line.
4. Ship that as a signed commit through a PR. Wait for every `ci.yml` job on the PR, merge it, then wait for the push
   run on `main` at the merge commit.
5. Tag that commit signed and push the tag: `git tag -s v<version> -m v<version> <sha>`, then
   `git push origin v<version>`. Never move or reuse a tag.
6. Watch the Release run (`gh run watch <id> -i 60`). Confirm `gh release view v<version> -R cjber/kiln-forever`
   lists `kiln-forever-<version>.tar.gz` and the notes match the changelog section.
7. To install it locally, run `install.sh` from the unpacked archive (or kiln's own installer) and have the user
   `/reload`. Kiln's install lives in `~/.local/share/kiln-forever/addons`, which the client's `KilnForever` links
   point at.
