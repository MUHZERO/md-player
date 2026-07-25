# Public repository readiness audit

Audit date: 2026-07-23

Overall readiness: **ready for public repository review**

pub.dev release status: technically valid; owner release-version and tag decisions remain

## 1. Environment and Git state

- Flutter 3.44.5 stable, Dart 3.12.2
- OpenJDK 21.0.10; Android compilation targets Java 17
- Android compile SDK 36; plugin minimum SDK 23
- Branch: `main`
- Remote: `git@github.com:MUHZERO/md-player.git`
- Local branch was 10 commits ahead of `origin/main` before this audit
- Working tree was clean before the audit; audit changes are intentionally
  uncommitted
- All commits use a GitHub noreply author address
- No history rewrite was performed or recommended

## 2. Files changed

- Repository hygiene: `.gitignore`, `.pubignore`, package metadata, dependency
  lock, and public GitHub files
- Documentation: README, CHANGELOG, CONTRIBUTING, SECURITY, example README,
  public DartDoc, fixture provenance, release checklist, and this report
- Example safety: neutral page naming, empty replaceable URL, debug-only
  cleartext configuration, no release debug signing, and untracked generated
  plugin registrant
- Validation support: release-packaging tests, safer runner validation/cleanup,
  sanitized phase-report location, and reproducible Pigeon output
- No playback, Media3, cache, quality-switch, lifecycle, or controls behavior
  changed

## 3. Secrets and privacy

Tracked files, pending diffs, sensitive filenames, URLs, and practical Git
history were scanned for API keys, bearer credentials, private keys, passwords,
keystores, environment files, private remotes, home paths, device serials, and
private IP addresses.

No real secret or credential was found. Test authorization values are obvious
placeholders. Contributor email addresses in `AUTHORS` are inherited public
attribution and were retained. One absolute Android SDK path was removed from a
phase report. No credential rotation or history cleanup is required.

## 4. Ignore and archive hygiene

`.gitignore` now covers Dart/Flutter output, project-local Gradle caches, IDE
files, coverage, logs, APK/AAB files, signing material, and generated Flutter
registrants. `.metadata` remains absent and deliberately unignored so a future
Flutter migration can review and track it if needed.

`.pubignore` removes internal tests, debug/device harnesses, reports, Gradle
state, signing/local properties, and binary media fixtures from the published
archive. It does not hide required Android source, Pigeon schema/output, public
Dart libraries, documentation, license, or the interactive example.

## 5. Package metadata and dependencies

- Canonical repository: `https://github.com/MUHZERO/md-player`
- Canonical issue tracker: `https://github.com/MUHZERO/md-player/issues`
- Package claims Android only
- No dependency override, git dependency, or release path dependency
- `flutter`: widget/plugin runtime
- `http`: Vimeo configuration resolution
- `meta`: required by generated Pigeon runtime code
- `video_player_platform_interface`: platform compatibility
- `youtube_explode_dart`: YouTube stream resolution
- `pigeon`: pinned development generator

The current version remains `2.7.3` as requested. Recommended first release
version: **0.1.0**, because this is a distinct package/fork and its public
release history should not imply that inherited upstream `2.7.x` entries were
releases of this package.

## 6. License and third-party material

The root BSD 3-Clause license is present and existing Flutter copyright headers
are preserved. No copyright holder was invented. AndroidX Media3,
`youtube_explode_dart`, Pigeon, Flutter, and other dependencies are referenced
as dependencies rather than vendored binary/source distributions, so no new
root `NOTICE` was identified as required.

Fixtures are generated specifically for tests from an FFmpeg test pattern and
synthetic tone. No downloaded YouTube media, speech, branding, or personal
metadata is included. FFmpeg is a contributor-only generation requirement.
README limitations neutrally call out provider availability and the
application's responsibility to comply with applicable content terms.

## 7. Public API and documentation

Both package entrypoints were audited. Pigeon types, rebuild diagnostics, and
integration helpers are not exported. The inherited low-level
`MdPlayerAndroid` API and `AndroidVideoPlayer` compatibility alias remain to
avoid a breaking change.

DartDoc now covers the package entrypoints, player/controller/value, source and
quality models, cache configuration/stats/facade, modern controls types,
fullscreen ownership, quality acceptance versus confirmation, volume/mute,
source resolution, Android registration, and asynchronous disposal.

`dart doc` documented both public libraries with **0 warnings and 0 errors**.

Potential future-major concerns were not changed: several public source/value
constructors accept mutable collections, and some low-level platform events are
public through the compatibility entrypoint. Defensive-copy or deprecation work
would be API-sensitive and is not required for this release.

## 8. README, changelog, and example

README now covers platform support, installation, lifecycle, direct and
YouTube sources, separate streams, manual quality, modern controls,
host-controlled fullscreen, cache management, Android requirements,
limitations, troubleshooting, testing, contributing, and licensing.

CHANGELOG uses an `Unreleased` section for fork behavior and labels older
entries as inherited upstream history. Media3 documentation matches version
1.10.1.

The example retains legacy and modern controls, cache configuration,
fullscreen/orientation restoration, custom labels/colors, and retry handling.
It has no default media URL or private configuration. The old mini controller
is integration-test support rather than public example code.

## 9. Android release audit

- Plugin namespace: `io.flutter.plugins.videoplayer`
- Plugin minimum SDK: 23
- Compile SDK: 36
- Java source/target: 17
- Media3: 1.10.1
- Main plugin manifest declares no permission or Android component
- Example main manifest uses normal `FlutterActivity`
- Example debug manifest alone replaces it with the lifecycle test activity
- Loopback cleartext rules for `127.0.0.1` and `10.0.2.2` are debug-only
- No broad cleartext production policy or storage permission exists
- Cache uses the application context and app-private cache directory
- No signing keys or release signing configuration are committed

The minified release APK contains no `debug_diagnostics` channel,
`example_lifecycle` harness, `IntegrationTestPlugin`, or JNI dev-plugin marker.
The release manifest contains no test activity or network-security override.

The local validation APK still bundles the repository's synthetic integration
fixtures because the same example app is the device harness. Those binaries
are excluded from the pub archive and are not runtime dependencies of the
plugin.

## 10. Pigeon and generated code

Tracked source: `pigeons/messages.dart`. Tracked outputs:

- `lib/src/messages.g.dart`
- `test/test_api.g.dart`
- `android/src/main/java/io/flutter/plugins/videoplayer/Messages.java`

Pigeon is pinned to 27.1.1. Regeneration, Dart formatting, and generated Java
trailing-whitespace normalization produced byte-identical outputs. Generated
headers are preserved and no stale schema output remains.

## 11. Fixtures, scripts, and reports

All five fixture checksums pass. Committed fixture payload is approximately
1.9 MB uncompressed and remains justified by deterministic device validation.
The deliberately corrupt MP4 is documented.

All four shell scripts pass `sh -n`. Runners quote paths and device IDs, reject
invalid repetition counts, validate fixtures/checksums, validate Android
targets, use unique ignored report paths, clean temporary files, and stop only
their owned server process. No `sudo`, recursive permission change, global
installer, `killall`, or `pkill` is used.

Phase reports are retained as sanitized engineering evidence under
`tool/reports/` and excluded from pub archives. No raw JSON/log report is
tracked.

## 12. Code-quality findings

Analysis is clean. No production TODO/FIXME was introduced. Existing generated
lint suppressions remain generator-owned. Stable large files include the
1,500-line modern-controls widget, the controller, and generated bindings;
splitting them during a release audit would add risk without measurable
behavioral value.

Inherited TLS compatibility code below the current minimum SDK and several
intentional stale-operation error swallows could be reviewed later, but neither
caused a correctness, security, or release failure. Existing lifecycle, lease,
listener, timer, rollback, and disposal tests remain authoritative.

## 13. Validation results

| Gate | Result |
| --- | --- |
| `dart format --output=none --set-exit-if-changed .` | Pass |
| Package analysis | Pass, 0 issues |
| Example analysis | Pass, 0 issues |
| Flutter tests | Pass, 67 tests |
| Android unit tests | Pass, 53 tests |
| Pigeon reproducibility | Pass, byte-identical |
| DartDoc | Pass, 0 warnings/errors |
| Fixture checksums | Pass, 5 files |
| Shell syntax | Pass, 4 scripts |
| `git diff --check` | Pass |
| Debug assembly | Pass |
| Release assembly | Pass |
| Plugin release AAR | Pass |
| Clean-copy pub dry-run | Pass, 0 warnings |

Gradle reports non-blocking warnings about Kotlin plugin compatibility,
deprecated Gradle features, Mockito's future agent-loading requirement, and an
Android SDK XML tooling-version mismatch. None failed tests, lint, or assembly.

## 14. Artifact and pub archive results

| Artifact | Approximate size |
| --- | ---: |
| Debug APK | 184 MB |
| Unsigned minified release APK | 53 MB |
| Release plugin AAR | 92 KB |
| pub.dev compressed archive | 125 KB |

The pub archive contains only production Android source, public Dart code,
Pigeon source/output, legal/docs files, and the clean interactive example.
Internal tests, reports, debug harnesses, local properties, and fixture binaries
are excluded.

The dry-run was repeated from a clean temporary copy because the audit changes
are intentionally uncommitted. It completed with **0 warnings**. Running the
same command directly in the working tree reports only expected dirty-Git
warnings until the final commit exists.

## 15. CI and repository governance

A minimal Ubuntu GitHub Actions workflow pins Flutter 3.44.5 and both third-
party actions by immutable commit SHA. It runs dependency resolution, format,
analysis, Flutter tests, generated-code verification, Android unit tests, and
the pub dry-run. It requires no secrets and runs no emulator.

`SECURITY.md` directs reports to GitHub private vulnerability reporting.
Concise bug-report and pull-request templates are present. A code of conduct
was not added because choosing a community governance policy belongs to the
owner and is not required for package correctness.

## 16. Device baseline

No new device suite was run because audit changes do not alter playback,
quality switching, cache behavior, lifecycle, or controls. Existing sanitized
reports remain the baseline:

- Phase 2.1: API 37 preview emulator
- Phase 3 cache: API 37 preview emulator plus physical Android API 36
- Phase 4 UI: API 37 preview emulator, including 1/3/10 repetitions

The prior Phase 4 result records one stable surface build across normal
position/UI updates. Public readiness does not claim that automated validation
proves subjective visual quality.

## 17. Remaining decisions and limitations

- Owner must choose the first public version; `0.1.0` is recommended.
- Owner must review and create the release tag.
- GitHub private vulnerability reporting must be enabled in repository
  settings for the documented form to work.
- API 37 preview remains the latest complete modern-controls device baseline.
- Public mutable source collections should be reconsidered only in a future
  breaking release.

None of these blocks publishing the repository for public review. Version/tag
selection blocks an actual pub.dev release ceremony, not package validation.

## 18. Commit and push commands

Review the complete diff, then publish it through a branch:

```bash
git switch -c chore/public-repo-readiness
git add -A
git diff --cached --check
git commit -m "chore: prepare package for public release"
git push -u origin chore/public-repo-readiness
```

Do not publish to pub.dev until the owner selects the version, updates
`pubspec.yaml` and `CHANGELOG.md` consistently, reruns the checklist, and plans
the matching Git tag.

## 19. SecondBrain

- Queried: yes
- Note consulted: `Projects/MD Player.md`
- Durable knowledge used: controller → platform/Pigeon → Media3 → texture flow,
  platform-interface compatibility, generated-code ownership, test boundaries,
  and the canonical repository mismatch
- SecondBrain edits: none
- Suggested update: after the public-readiness change is reviewed, record the
  canonical repository URL, clean pub dry-run, CI gates, and selected release
  version in the existing project note and daily note
