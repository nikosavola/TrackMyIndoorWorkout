# TrackMyIndoorWorkout — Proposed Improvement Issues

Based on a full-repo analysis (CI/CD config, build files, `lib/` architecture, security posture, test coverage, dependency/performance review). 13 issues, grouped by theme.

---

## 1. [DevOps] Modernize the CI workflow: stale action pins, no caching, no build verification

**Labels:** `devops`, `ci`

### Problem
`.github/workflows/flutter_test.yml` runs on every push/PR but has drifted:
- `actions/checkout@v2` (EOL, Node 12 runner)
- `actions/setup-java@v2` (deprecated; current is v4)
- `subosito/flutter-action@v1` (current major is v2, which adds built-in SDK/pub caching)
- No `actions/cache` for `~/.pub-cache` or Gradle — every run does a cold `flutter pub get`
- A build-verification step exists but is commented out:
  ```yaml
  #- name: Build App Bundle (debug)
  #  run: flutter build appbundle
  ```
  so a change can pass analyze/format/test and still fail to actually build.
- `integration_test/` is never invoked in CI.
- Single `ubuntu-latest` job only — no matrix, no macOS/iOS build check.

### Proposed change
- Bump `actions/checkout` to v4/v5, `actions/setup-java` to v4, `subosito/flutter-action` to v2 with `cache: true`.
- Re-enable an app/appbundle build step (behind the mocked secret file) so build breakage is caught pre-merge.
- Add a job (or step) that runs `flutter test integration_test/` where feasible, or at minimum keep it building.
- Pin the Flutter channel/version explicitly (`flutter-version-file: pubspec.yaml` or an explicit version) instead of a floating `stable` channel, so CI doesn't silently break on upstream Flutter releases.

### Acceptance criteria
- [ ] All GitHub Actions pinned to current major versions
- [ ] Pub/Gradle caching enabled, measurable CI time reduction
- [ ] A build step runs on every PR and fails the job on build errors
- [ ] Flutter version is pinned/reproducible, not a floating channel

---

## 2. [DevOps/Testing] Add code coverage measurement and reporting

**Labels:** `devops`, `testing`

### Problem
`flutter test` runs in CI (`flutter test --dart-define=testing_mode=true`) without `--coverage`. There is no `lcov.info` generation, no Codecov/Coveralls upload, and no coverage badge or threshold anywhere in the repo (README, pubspec.yaml, and workflow all confirmed clean of any coverage reference). With ~130 test files against ~384 non-generated source files, there's no visibility into which of that ~1:3 ratio is meaningfully exercised vs. superficially imported.

### Proposed change
- Run `flutter test --coverage --dart-define=testing_mode=true` in CI.
- Upload `coverage/lcov.info` to Codecov (or Coveralls) and add a status check / badge to the README.
- Optionally set a minimum coverage gate for new PRs (via Codecov's PR-diff coverage, not a hard repo-wide threshold, to avoid blocking on legacy gaps).

### Acceptance criteria
- [ ] Coverage report generated and uploaded on every CI run
- [ ] Coverage badge visible in README
- [ ] Coverage trend visible over time (Codecov/Coveralls dashboard)

---

## 3. [Security/DevOps] Add automated dependency & code security scanning

**Labels:** `security`, `devops`

### Problem
- `.github/dependabot.yaml` only configures the `pub` ecosystem (weekly). There is **no `github-actions` ecosystem entry**, so the stale action pins in Issue #1 will never be auto-flagged by Dependabot, and no `gradle` ecosystem entry for native Android deps.
- No CodeQL workflow, no `dependency-review-action`, no secret-scanning workflow exists anywhere under `.github/`.
- No `SECURITY.md` describing how to report vulnerabilities responsibly.

### Proposed change
- Add a `github-actions` update block to `dependabot.yaml`.
- Add a CodeQL analysis workflow for Dart/Java/Kotlin where supported, or at minimum `actions/dependency-review-action` on PRs.
- Add a `SECURITY.md` with a disclosure contact/process.

### Acceptance criteria
- [ ] Dependabot covers `pub` and `github-actions`
- [ ] A security-scanning workflow runs on PRs
- [ ] `SECURITY.md` published

---

## 4. [DevOps] Automate the release pipeline and fix debug-signed release builds

**Labels:** `devops`, `security`

### Problem
- `android/app/build.gradle.kts` release build type: `signingConfig = signingConfigs.getByName("debug")`, with the comment *"Signing with the debug keys for now, so `flutter run --release` works."* There is no `key.properties`, no keystore reference, and no CI secret-based signing config anywhere — meaning any "release" build (including via CI, if the commented-out build step from Issue #1 were re-enabled) would ship signed with the publicly-known Flutter debug key, not a real release key.
- iOS `project.pbxproj` has no `CODE_SIGN_STYLE`/`DEVELOPMENT_TEAM` set, so there is no path to an automated/CI IPA build either.
- No Fastlane setup, no `deploy*.sh`/`release*.sh`, no store-upload automation exists. Releases are entirely manual today (versioning is manual, per `CHANGELOG.md`).

### Proposed change
- Introduce a real release signing config for Android, backed by a keystore stored as an encrypted CI secret and referenced via `key.properties` (gitignored) — falling back to debug signing only for local `flutter run --release` via a Gradle flavor/property check, not as the shipped default.
- Add a Fastlane (or GitHub Actions-native) release lane that builds a signed AAB/IPA on tag push and optionally uploads to Play Store internal testing / TestFlight.

### Acceptance criteria
- [ ] Release builds use a real signing key, sourced from secrets, not the debug key
- [ ] A tag-triggered workflow produces a signed, installable release artifact
- [ ] Release process documented in README (replacing the current fully-manual steps)

---

## 5. [DevOps] Repository hygiene: remove stale artifacts, add community health files

**Labels:** `devops`, `chore`

### Problem
- `PlayStoreDataSafetyReport15062022223003.csv` (173 KB, 763 lines) sits at the repo root, dated June 2022 — a one-off Play Console export that doesn't belong in version control (and is unrelated to `.privado/reports/playstore-data-safety.yaml`, which appears to be its intended replacement/successor).
- No `CODEOWNERS`, no `ISSUE_TEMPLATE`, no `PULL_REQUEST_TEMPLATE.md` under `.github/` — despite the README asking external contributors to coordinate before large PRs, there's no structured template to capture that.

### Proposed change
- Remove (or move to `docs/archive/`) the stale CSV export.
- Add `.github/ISSUE_TEMPLATE/bug_report.md` and `feature_request.md`, plus a `PULL_REQUEST_TEMPLATE.md` reflecting the format/analyze/test steps already required by the README's contribution rules.
- Add `CODEOWNERS` if there's a defined maintainer set.

### Acceptance criteria
- [ ] Stale CSV removed from the repo root
- [ ] Issue and PR templates in place

---

## 6. [Security] Store third-party OAuth tokens in encrypted/secure storage

**Labels:** `security`

### Problem
The app integrates with four OAuth-based fitness portals (Strava, Suunto, TrainingPeaks, Under Armour). Access/refresh tokens are persisted via the `pref` package (backed by `shared_preferences`), e.g.:
- `lib/upload/strava/oauth.dart:52-55` — `stravaAccessTokenTag`/`stravaRefreshTokenTag`/`stravaExpiresAtTag`
- `lib/upload/suunto/oauth.dart:41-43`
- `lib/upload/training_peaks/oauth.dart:56-59`
- `lib/upload/under_armour/oauth.dart:41-43`

`shared_preferences` stores data in an **unencrypted** XML file on Android and an unencrypted plist on iOS. No `flutter_secure_storage` (or platform Keychain/Keystore-backed) dependency exists in `pubspec.yaml`. A device compromise, backup extraction, or a malicious app with storage access (on rooted/older Android) can read live OAuth tokens for all four connected fitness accounts.

### Proposed change
- Introduce `flutter_secure_storage` (Keychain on iOS, EncryptedSharedPreferences/Keystore on Android) specifically for the access/refresh token + expiry fields, keeping `pref`/`shared_preferences` for non-sensitive UI preferences as-is.
- Migrate existing stored tokens on first launch after the update (read old key, write to secure storage, delete old key).

### Acceptance criteria
- [ ] OAuth tokens for all 4 providers stored via secure storage
- [ ] One-time migration path for existing installs
- [ ] No regression in silent token refresh flows

---

## 7. [Security] Harden OAuth redirect handling and platform permission disclosures

**Labels:** `security`

### Problem
Several smaller but compounding issues around the OAuth/deep-link and permission surface:
- OAuth redirects use custom URL schemes (`stravaflutter`, `suuntoflutter`, `mapmyfitnessflutter`, `trainingpeaksflutter`) registered in `AndroidManifest.xml` with `host="redirect"`, `pathPattern="/.*"`, and no `android:permission` guard. Custom URL schemes are not exclusive to one app on Android — another installed app registering the same scheme could intercept the OAuth redirect (and the authorization code in it). Migrating to verified Android App Links / iOS Universal Links (HTTPS-based, domain-verified) would close this off; if that's not feasible short-term, at minimum validate `state`/PKCE parameters strictly on every redirect (confirm this already happens — the audit didn't find evidence it does).
- `ios/Runner/Info.plist`: `NSBluetoothAlwaysUsageDescription` / `NSBluetoothPeripheralUsageDescription` both read the generic placeholder *"We need BT access because it's a BT App."* — Apple App Review increasingly rejects non-descriptive usage strings, and it doesn't build user trust for what is effectively a health-adjacent app.
- The app requests `ACCESS_FINE_LOCATION` on Android (needed for BLE scanning pre-Android 12) but `Info.plist` has **no** `NSLocationWhenInUseUsageDescription` at all — an iOS parity gap (if location is used there too) or dead permission on Android (if not actually needed) worth clarifying either way.
- `LSApplicationQueriesSchemes` in `Info.plist` includes plain `http` — should be removed if unused, since it widens the app's queryable-scheme footprint for no benefit.

### Proposed change
- Evaluate migrating OAuth redirects to Android App Links / iOS Universal Links.
- Confirm and, if missing, enforce PKCE `code_verifier`/`state` validation on every provider's redirect handler.
- Write accurate, specific `Info.plist` usage-description strings.
- Add `NSLocationWhenInUseUsageDescription` if location is genuinely used on iOS, or confirm/document why Android requests it but iOS doesn't.
- Remove unused `http` from `LSApplicationQueriesSchemes`.

### Acceptance criteria
- [ ] OAuth redirect interception risk documented/mitigated (App Links or verified state/PKCE)
- [ ] All iOS usage-description strings are specific and accurate
- [ ] No unused entries in `LSApplicationQueriesSchemes`

---

## 8. [Stability] Fix leaked `Timer`/subscription lifecycle in `FitnessEquipment`

**Labels:** `bug`, `stability`

### Problem
`lib/devices/gadgets/fitness_equipment.dart` declares `_timer` (line 88) and `_throttleTimer` (line 139) plus a `subscription` field. `_timer` is cancelled in `stopWorkout()` (line 1578), but:
- **`_throttleTimer` is never cancelled anywhere in the file** (only created at line 259 / read at 421).
- `detach()` (line 1582) only detaches companion sensors and calls `super.detach()` — it does **not** cancel `_timer`, `_throttleTimer`, or `subscription`. Any code path that detaches a device without first calling `stopWorkout()` leaves these alive, continuing to fire callbacks against a device that's no longer attached (and, per `git log` commit `78725f4`, this class of bug has already caused a "Null check operator used on a null value" crash on cross-trainer disconnect).

### Proposed change
- Cancel `_throttleTimer` and `subscription` in `detach()` (and/or a shared private `_cancelTimers()` helper called from both `stopWorkout()` and `detach()`), not just in the workout-stop path.
- Add a regression test that attaches a `FitnessEquipment`, starts the throttle timer, calls `detach()` without `stopWorkout()`, and asserts no further callbacks fire and no timer is pending.

### Acceptance criteria
- [ ] `detach()` tears down all timers/subscriptions unconditionally
- [ ] Regression test covers detach-without-stop
- [ ] No behavior change for the normal stop→detach path

---

## 9. [Code Quality] Break up the `recording_screen.dart` god-widget (3111 lines)

**Labels:** `refactor`, `code-quality`

### Problem
`lib/ui/recording/recording_screen.dart` is 3111 lines — the largest hand-written file in the project. Its `State` class declares 100+ instance fields, holds a raw `Isar` handle directly (`Get.find<Isar>()`), drives `FitnessEquipment`/`HeartRateMonitor`/`DeviceInternalMotion` directly, and even does `Get.put<FitnessEquipment>(..., permanent: true)` from inside the widget. `build()` alone is ~597 lines, and `_recordHandlerFunction` is ~200 lines mixing statistics/calorie/lap logic with UI state. This makes the file hard to review, test, or safely modify — most bug fixes in this area (see `git log`, several recent commits touch this file) require reasoning about the whole class at once.

### Proposed change
- Extract device orchestration (attach/pumpData wiring) into a controller/service class the widget consumes, rather than owning it directly.
- Extract the per-record statistics/lap/calorie logic out of `_recordHandlerFunction` into a testable, UI-independent class (there's precedent — `record_statistics_accumulator` already exists and is tested; consolidate more of this logic there).
- Split `build()` into named sub-widgets per screen region (already partially done per the CHANGELOG's "Refactor the recording screen into a separate directory" — continue that effort into the main file itself).

### Acceptance criteria
- [ ] `recording_screen.dart` reduced substantially in line count via extraction (target: no single file/method dominates)
- [ ] Extracted logic has unit tests independent of widget rendering
- [ ] No behavior regression (manual + existing test suite green)

---

## 10. [Code Quality] Consolidate state management and extract a domain layer from `DbUtils`

**Labels:** `refactor`, `code-quality`

### Problem
- State management is inconsistent: exactly **1** class (`FindDevicesController`) uses GetX reactively (`extends GetxController`); everywhere else (44 `StatefulWidget`s) it's plain `setState()` (120 call sites across `lib/ui/`), while GetX is otherwise used purely as a service locator (`Get.put`/`Get.find`). This means two different mental models for "how does UI update" coexist, increasing onboarding cost and making `Obx`/reactive optimizations unavailable where they'd help most (e.g. the recording screen, which rebuilds via `setState` on every throttled BLE sample).
- `lib/persistence/db_utils.dart` (`DbUtils`, with `PowerSpeedMixin`) mixes low-level Isar access with domain logic: `recalculateCumulative`, `bridgeDataGaps`, `powerFactor`/`calorieFactorValue`, `finalizeActivity`, `splitActivity`, `offsetActivity` — i.e., activity-splitting and calorie/power-factor computation live in what should be a persistence-only utility class.

### Proposed change
- Pick one primary state-management pattern going forward (either lean further into GetX's reactive primitives — `.obs`/`Obx`/`GetBuilder` — or drop GetX's reactivity claim entirely and standardize on `setState`/a dedicated notifier per screen). Document the choice in `README.md`'s contribution rules.
- Extract the business-logic methods out of `DbUtils` into a separate domain/service class (e.g. `ActivityCalculator`/`ActivityEditor`), leaving `DbUtils` as a thin persistence-only wrapper.

### Acceptance criteria
- [ ] A documented, single state-management convention for new UI code
- [ ] `DbUtils` reduced to persistence-only responsibilities; extracted logic independently unit-tested

---

## 11. [Testing] Add coverage for `lib/upload/*` OAuth and portal-upload integrations

**Labels:** `testing`

### Problem
`lib/upload/` (29 files: Strava, Suunto, TrainingPeaks, Under Armour subdirectories + `upload_service.dart`) has **zero** test coverage. Only one unrelated sport-mapping enum (`training_peaks.dart`) is exercised by `test/training_peaks_sport_test.dart`. None of the OAuth flows (`*/oauth.dart` — token exchange, refresh, redirect handling), and none of the actual upload/serialization logic (`*/upload.dart`, `*/upload_activity.dart`) have any test. This is the code responsible for authenticating against and pushing user workout data to four external services — exactly where a silent regression (e.g. a broken token refresh, or a malformed upload payload) would be highest-impact and hardest to notice locally, since it can only be observed via a live account round-trip.

### Proposed change
- Add unit tests for each provider's OAuth token-refresh logic using `mocktail` to fake the `http.Client`, covering: successful refresh, expired-refresh-token failure, and malformed-response handling.
- Add unit tests for the upload-payload construction/serialization logic (independent of the actual HTTP call), verifying the request body/headers match each provider's API contract.

### Acceptance criteria
- [ ] Each of the 4 providers has OAuth-flow unit tests
- [ ] Each of the 4 providers has upload-payload unit tests
- [ ] Coverage report (Issue #2) shows non-zero coverage for `lib/upload/`

---

## 12. [Testing] Replace the placeholder integration test with real end-to-end coverage

**Labels:** `testing`

### Problem
`integration_test/app_test.dart` (33 lines) is the **unmodified default Flutter counter-app template** — it launches `app.main()` and asserts a `+` FAB increments a counter from `0` to `1`. It exercises none of this app's actual screens (device scanning, recording, activity detail, export/import, upload). Despite `integration_test`/`flutter_driver` being wired into `pubspec.yaml` and a driver file existing, there is effectively no automated end-to-end coverage of the app today, and CI doesn't even run this target (see Issue #1).

### Proposed change
- Replace the counter test with real flows: app launch → simulated/mock device scan and connect → start/stop a recording → verify an activity is persisted and visible in the activity list → export to at least one format.
- Wire `integration_test/` execution into CI (ties into Issue #1).

### Acceptance criteria
- [ ] Placeholder counter test removed
- [ ] At least one real end-to-end flow (scan→record→save→view) covered
- [ ] Integration tests run in CI

---

## 13. [Performance] Batch or move Isar writes off the live-recording hot path

**Labels:** `performance`

### Problem
During an active recording, every throttled BLE sample (`FTMS_DATA_THRESHOLD`, default 480 ms, configurable 50–1000 ms) triggers a **synchronous** Isar write transaction directly inside the UI callback:
- `lib/ui/recording/recording_screen.dart:355-357` — `_database.writeTxnSync(() { _database.records.putSync(record); })` inside `_recordHandlerFunction`, immediately followed by a `setState()` (line 387) that also mutates `_graphData`.
- `lib/devices/gadgets/fitness_equipment.dart:1041-1043` — a second synchronous write (`database.activitys.putSync(_activity!)`) on the moving/not-moving state-transition path.

`writeTxnSync` blocks the calling thread until the transaction commits. Running one disk-write transaction roughly every 0.5–1s on the same thread that also drives a `setState()`-triggered widget rebuild (and, per Issue #10, no reactive/selective-rebuild alternative exists) stacks I/O latency directly onto UI-thread work during the app's core, most latency-sensitive feature — live workout recording.

### Proposed change
- Batch record writes (e.g. accumulate N records or T milliseconds, then a single `writeTxnSync` for the batch) rather than one transaction per sample, or move the write onto Isar's async `writeTxn` off the UI-critical path with an in-memory buffer feeding the chart immediately.
- Profile with Flutter DevTools during a live recording session (BLE simulator or real device) before/after to confirm reduced frame-time variance.

### Acceptance criteria
- [ ] Record persistence batched or moved off the synchronous UI-callback path
- [ ] No data loss on ungraceful app termination (batching must not risk losing more than one throttle interval of data)
- [ ] Before/after profiling shows reduced jank during recording
