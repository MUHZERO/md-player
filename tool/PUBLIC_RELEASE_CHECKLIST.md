# Public release checklist

Status reflects the public-repository audit completed on 2026-07-23.

## Repository and legal

- [x] Tracked files, pending changes, remotes, branch, and recent history audited
- [x] Tracked files and practical Git history scanned for secrets/private data
- [x] Root BSD 3-Clause license present
- [x] Existing Flutter attribution and generated-code headers preserved
- [x] Synthetic fixture provenance and checksums documented
- [x] Repository and issue-tracker URLs configured
- [ ] Owner has selected the first public release version
- [ ] Release tag has been planned and created

## Package

- [x] Package description, topics, platforms, and SDK constraints are accurate
- [x] Runtime and development dependencies are necessary and release-safe
- [x] No git/path dependency or dependency override is present in release metadata
- [x] README and CHANGELOG match current behavior
- [x] Meaningful public APIs have DartDoc
- [x] Legacy controls remain the default; modern controls remain opt-in
- [x] Android-only support and limitations are explicit
- [x] Cache, quality confirmation, fullscreen ownership, and disposal semantics are documented
- [x] pub.dev dry-run passes from a clean tree with no warnings

## Android and example

- [x] Debug diagnostics are not exported and are absent from the minified release APK
- [x] Debug lifecycle activity and loopback cleartext policy are debug-only
- [x] Release build has no committed signing configuration
- [x] Example contains no default private or third-party media URL
- [x] Example restores its declared orientation policy
- [x] Generated Flutter plugin registrant is ignored rather than tracked
- [x] Debug APK, unsigned release APK, and release plugin AAR assemble

## Generated code and validation

- [x] Pigeon schema and required Dart/Java outputs are tracked
- [x] Pigeon 27.1.1 generation command is documented and reproducible
- [x] Fixture checksums pass
- [x] Shell syntax and invalid-argument checks pass
- [x] `dart format --output=none --set-exit-if-changed .` passes
- [x] Package and example analysis pass
- [x] All Flutter tests pass
- [x] All Android unit tests pass
- [x] `git diff --check` passes
- [x] Existing device-validation status is documented in sanitized phase reports

## GitHub

- [x] Minimal pinned GitHub Actions validation workflow exists
- [x] Security reporting instructions use GitHub private vulnerability reporting
- [x] Bug-report and pull-request templates exist
- [x] Contribution instructions are standalone and current
- [ ] Final readiness change has been reviewed and committed
- [ ] Public branch has been pushed and reviewed
