# Publish the V2 Lens public beta

Use this checklist to publish the already-prepared `v0.1.0-beta.1` source
release. It does not create native installers or a Racket catalog entry.

## Prerequisites

- Use Racket 9.2 and an authenticated `gh` CLI.
- Enable GitHub private vulnerability reporting.
- Confirm the Windows, macOS, and Linux CI jobs pass for the release commit.
- Work from a clean clone of `main` with no staged or unstaged changes.

## Verify the release commit

```sh
raco pkg install --auto --copy --name v2-lens "$PWD"
raco setup --check-pkg-deps --pkgs v2-lens
raco test -p v2-lens
git status --short
```

The test command must pass and `git status --short` must print nothing. Confirm
that `CHANGELOG.md` still describes the intended beta contents.

## Create and publish the prerelease

```sh
git tag -a v0.1.0-beta.1 -m "V2 Lens v0.1.0-beta.1"
git push origin v0.1.0-beta.1
gh release create v0.1.0-beta.1 \
  --repo CodeDraig/v2-lens \
  --prerelease \
  --verify-tag \
  --title "V2 Lens v0.1.0-beta.1" \
  --notes-file .github/release-notes/v0.1.0-beta.1.md
```

## Verify the published tag

In a clean Racket 9.2 user environment, run:

```sh
raco pkg install --auto https://github.com/CodeDraig/v2-lens.git#v0.1.0-beta.1
racket -e '(require v2-lens) (displayln (hl7-parse-result-complete? (parse-hl7-v2 "MSH|^~\\&|APP")))'
```

The final command must print `#t`. Confirm the GitHub release is marked as a
prerelease and that all three tagged-commit CI jobs pass.
