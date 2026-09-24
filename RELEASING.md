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


## Build native test packages

Use a native Racket 9.2 CS installation with `gui-lib`, Python 3.12+, and Git.
On Linux use Ubuntu 22.04 or a compatible build baseline with GTK 3 available.
On macOS install the command line developer tools for `codesign` and `otool`.
Run from a clean checkout:

```sh
python3 scripts/package.py
python3 scripts/verify-package.py target/packages/V2-Lens-0.1.0-beta.1-macos-arm64.zip
```

Use `python` on Windows. Select the generated archive matching your platform;
Linux uses `.tar.gz` and verification needs a display (or `xvfb-run -a`).
Versioned outputs and SHA-256 checksums are written to `target/packages/`.
The build uses `raco exe` followed by `raco distribute` to include the runtime.
Mac framework layout and application metadata are completed before ad-hoc
signing. The verifier extracts the archive, checks its checksum and Mac code
signature/dependencies, and exercises the actual GUI launcher from an empty
working directory with no Racket tools or user collections on its search path.

The **Native packages** workflow performs this on Mac ARM64 and x64, Windows
x64, and Linux x64. Separate fresh runners download and test each archive
without installing Racket or checking out application source. All eight jobs
must pass before handing artifacts to testers. The workflow runs on pushes,
pull requests and manual dispatch; it does not publish a release automatically.

`VERSION` controls archive names and application release metadata. Each archive
includes `build-info.json` with the commit, dirty state, architecture, runtime
version and signing type. Do not hand off a build marked `dirty: true`.
Archives include the application license, runtime notices and tester directions.
Update the release notes and version together before the next release.

These are portable beta archives, not installers. Mac builds use ad-hoc signing;
Windows builds are unsigned. Developer ID signing/notarization and Windows
publisher signing require signing credentials and are separate distribution
steps. Do not describe these artifacts as notarized or publisher-signed.
