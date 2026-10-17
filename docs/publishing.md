<!-- SPDX-License-Identifier: CC-BY-4.0 -->

# Publishing a release

Mirinae ships without a Developer ID. Two install paths cover that: a Homebrew formula that
builds on the user's Mac (no Gatekeeper prompt, because a locally built app is never
quarantined), and a prebuilt zip for people who want it faster and accept one "Open Anyway".

## 1. Tag and package

```sh
# bump CFBundleShortVersionString in Resources/Info.plist and update CHANGELOG.md first
Scripts/test.sh
git commit -am "Release <version>"
git tag v<version>
git push origin main v<version>
```

Pushing the tag runs `.github/workflows/release.yml`, which tests, builds a universal
(arm64 and x86_64) bundle, verifies the signature, signs the zip with Sigstore, writes
`build/SHA256SUMS` with the zip and the source tarball, and creates the GitHub release with
generated notes. To do the same by hand: `Scripts/package.sh` refuses to run unless HEAD is
tagged with the version in `Info.plist`, so the zip always matches a tag. A local package has
no attestation, only the workflow can produce one.

Every build records the commit in the bundle (`MirinaeGitCommit` in `Info.plist`) and uses the
commit count as `CFBundleVersion`, so two builds of the same tag are identifiable even
though Swift builds are not bit-for-bit reproducible.

The release's `SHA256SUMS` has both values the tap needs: the zip for the cask and the
source tarball for the formula.

## Provenance attestations

The workflow runs `actions/attest` on the zip, in its default provenance mode. That signs
the zip's digest with a short-lived Sigstore certificate tied to this repository, the tag,
and the workflow file, and records the signature in the public Rekor transparency log.
GitHub stores the resulting SLSA provenance attestation on the repository, and the workflow
also attaches the bundle to the release as `Mirinae-<version>.zip.sigstore.json`.

Releases are immutable on this repository, so the tag and the assets are locked once the
release is published. `gh release create` creates a draft, uploads every asset, and only
then publishes, so the whole set lands in one go. If the workflow fails before that point,
nothing is published and the tag can still be deleted and recreated.

Anyone can check that a zip came out of this repository's release workflow and was not
modified since:

```sh
gh attestation verify Mirinae-<version>.zip --repo agriyakhetarpal/mirinae
```

Without `gh`, the bundle on the release page works with cosign:

```sh
cosign verify-blob-attestation --bundle Mirinae-<version>.zip.sigstore.json \
  --certificate-identity-regexp '^https://github.com/agriyakhetarpal/mirinae/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --type slsaprovenance1 Mirinae-<version>.zip
```

This is separate from Apple's code signing. The bundle inside the zip is still ad hoc
signed and not notarised, so the Gatekeeper step in the README stays. The attestation tells
you who built the zip, Gatekeeper is about whether Apple has seen it.

## 2. The tap

Create a repository named `homebrew-tap` under your account with this layout:

```
Formula/mirinae.rb    from packaging/homebrew/Formula/mirinae.rb
Casks/mirinae.rb      from packaging/homebrew/Casks/mirinae.rb
```

Update the version and both SHA-256 values, commit, push. Users then run:

```sh
brew install agriyakhetarpal/tap/mirinae            # builds from source, no prompt
brew install --cask agriyakhetarpal/tap/mirinae     # prebuilt, one "Open Anyway"
```

A personal tap has no popularity requirement. Homebrew's official repositories want 75
stars (225 if you submit your own project), so that is a later step.

## 3. What users need

- macOS 14 or newer, Apple silicon or Intel.
- For the formula: the Command Line Tools, which Homebrew installs anyway. Full Xcode is
  not needed. The code avoids the one SwiftUI feature whose compiler plugin ships only with
  Xcode.
- For the cask: nothing, plus the one-time Gatekeeper step.

## Checklist before tagging

- `Scripts/test.sh` passes.
- `python3 Scripts/check-strings.py` passes if any translations exist.
- `python3 Scripts/extract-strings.py` has been run after the last UI text change.
- The app connects, renames, refreshes, and the watcher launches it, on a real pair.
