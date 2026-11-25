# Sangaso Android QA Report — Local Emulator Repair

**Date:** 2026-11-25
**Device:** `emulator-5554` (AVD `Sangaso_Pixel6`, Android API 37, x86_64 Google Play image)
**Package:** `com.sangaso.app`
**Backend under test:** Firebase emulators only — project `demo-sangaso-local`, Auth `127.0.0.1:9099`, Firestore `127.0.0.1:8080`
**Production Firebase:** NOT contacted by any local workflow in this report.

## 1. Local harness repair — PASS

| Item | Result | Evidence |
|---|---|---|
| Android emulator host default `10.0.2.2` | PASS | `lib/main.dart` |
| Desktop/web host default `localhost` | PASS | `lib/main.dart` |
| `SANGASO_EMULATOR_HOST` override (env + `--dart-define`) | PASS | `lib/main.dart`, `local-test/README.md` |
| Production behaviour unchanged when flag unset | PASS by inspection | `lib/main.dart` — all emulator calls inside `if (useEmulators)` |
| Emulator mode initializes `demo-sangaso-local` project | PASS | `lib/main.dart`, commit `201a82d` |
| Auth + Firestore emulators only | PASS | `local-test/emulator-run.log` |
| Storage emulator not started/configured | PASS | `local-test/firebase.json` |
| Deploy targets removed from local harness | PASS | `local-test/firebase.json` has no `firestore`/`storage` deploy sections |
| Permissive rule files untracked and ignored | PASS | `git ls-files local-test` and `git check-ignore` |
| Fake credentials outside Git | PASS | `local-test/fake-credentials.local.json`, `local-test/.gitignore` |

The emulator run logs: “All emulators ready!” for Authentication and Firestore only. Firestore uses the emulator’s built-in local allow-all behaviour; no rule file is supplied or deployable from `local-test/`.

## 2. Auth seed results — PASS

`node seed.js` completed successfully.

- Created/updated both Auth Emulator accounts with `emailVerified: true`.
- Verified both passwords through the Auth Emulator sign-in REST endpoint.
- Created `/users/{actualAuthUid}` documents for seeker and provider.
- Set all three seeded service `providerId` values to the actual provider UID.
- Firestore verification: 2 users, 3 services, all verified and linked.

Seed evidence: `evidence/emulator-seed.utf8.log`.
Baseline Firestore snapshot: `evidence/firestore-before-workflows.json`.
Post-launch snapshot: `evidence/firestore-after-launch.json` — matches the baseline except for `capturedAt`; still 2 users, 3 services, 0 bookings, 0 notifications.

The credentials remain in the ignored file `local-test/fake-credentials.local.json`; no password is recorded in this report or in Git.

## 3. Repaired APK build and installation

| Check | Result |
|---|---|
| Fork QA run `45614107494` (first build) | Analyze FAILED (pre-existing lints); `flutter test`, APK build and upload PASSED |
| Fork QA run `45637734491` (corrected demo-project build) | Analyze FAILED (pre-existing lints); `flutter test`, APK build and upload PASSED |
| APK package | `com.sangaso.app` |
| APK version | `1.0.3+8` (QA build, not a Play release build) |
| APK size | 155,875,228 bytes |
| APK SHA-256 | `4A3A8AF80A78D5AB2FFDE484C5971E19B47A9C2B8B0F708BB448AD9A754647AD` |
| APK debug certificate SHA-256 | `e88de99206b1d2c1ef51b367ce575f71d52bc9d9b683f414af0415d47241e196` |
| Prior installed certificate | `29632dcfd5ab046ed140d49823be92242c065806b5014841511bfa4ce4df17cb` |
| Uninstall/reinstall approval | Owner approved; old app uninstalled and corrected APK installed |
| Install result | PASS (`evidence/apk-install-v2.log`) |

The APK is deliberately built with `--dart-define=SANGASO_USE_EMULATORS=true --dart-define=SANGASO_EMULATOR_HOST=10.0.2.2`. It is a local QA artifact only and must not be uploaded to Play.

## 4. Android workflow test results

All Android workflow tests are **NOT TESTED / BLOCKED** in this run. The repaired APK installed successfully, but the emulator repeatedly showed “Process system isn't responding” for `system_server`, then “Pixel Launcher isn't responding” and “System UI isn't responding” after the AVD eventually completed boot. A final direct `am start -n com.sangaso.app/.MainActivity` was accepted by Activity Manager, but the ANR overlay remained focused and the app never reached a usable UI. Evidence: `evidence/local-launch1.png`, `evidence/local-final-launch.png`, `evidence/ui-launch1.xml`–`ui-launch4.xml`, `evidence/ui-final-state.xml`, `evidence/ui-final-wait.xml`, `evidence/ui-final-launch.xml`. This is the same host-starvation class of failure recorded on 22 November, not an observed app `FATAL EXCEPTION`. Firestore remained at the seeded baseline after the final attempt.

| Test | Status | Detail |
|---|---|---|
| Seeker login | BLOCKED | App UI unavailable after launch; no auth operation attempted |
| Provider login | BLOCKED | Same |
| Session persistence | NOT TESTED | Requires successful sign-in |
| Logout and relogin | NOT TESTED | Requires successful sign-in |
| Marketplace | NOT TESTED | App UI unavailable |
| Search and categories | NOT TESTED | App UI unavailable |
| Provider profile | NOT TESTED | App UI unavailable |
| Booking form | NOT TESTED | App UI unavailable |
| Booking creation | NOT TESTED | No booking created |
| Booking history | NOT TESTED | No booking created |
| Booking details | NOT TESTED | No booking created |
| Cancellation | NOT TESTED | No booking created |
| Provider notification | NOT TESTED | No booking created |
| Provider-side booking visibility | NOT TESTED | No booking created |
| Booking status consistency | NOT TESTED | No booking created |

No production booking test was performed, and no local emulator result is claimed as a production pass.

## 5. Build workflow repair

`app/.github/workflows/build.yml` now contains the required Java 17 setup step before Flutter setup in **both** `build` and `release` jobs (commit `a88fbec`, branch `fix/sangaso-full-repair-2026-11-22`).

Upstream push/run remains BLOCKED pending the owner-approved GitHub workflow-scope refresh for the `drizzlysean` account. The fork branch was updated and both fork QA runs completed test/build/upload successfully.

## 6. Play release preparation — BLOCKED

- VersionCode 9 availability was **not** confirmed: Play Console was not authenticated in the browser.
- Four signing secret names are present in `build.yml`; existence of actual repository secret values was **not** verified because upstream GitHub scope is pending.
- No upload keystore was found in the local workspace; keystore non-empty/keytool alias checks are BLOCKED.
- No signed release AAB was built and no Play upload was attempted.
- Play App Signing SHA-1 registration in Firebase was **not** verified.

## 7. Live Firebase investigation — BLOCKED

`firebase login:list` still reports “No authorized accounts”. `firebase login` was started and a Google sign-in tab was opened (session `11B98`); owner completion and the returned authorization code are required.

Consequently the following remain unverified: access to `ondemand-a16d1`, deployed Firestore/Storage rules and indexes, comparison with the older public candidate rules, the authorized test account state, and whether live rules allow whole-user-document updates including `role` changes. No rules were published.

## 8. Final readiness

**NOT READY — CRITICAL DEFECTS REMAIN.** No production deployment, rules publication, or Play upload was performed. Local harness and APK installation are repaired and verified, but interactive Android workflows, upstream workflow validation, live Firebase investigation, and release preparation remain blocked as recorded below.

## 9. Unresolved issues

1. Emulator `system_server`/launcher/System UI ANRs under host starvation block all interactive Android workflow tests.
2. GitHub workflow-scope device authorization was not completed before the device code expired; upstream workflow push/run is blocked.
3. Firebase CLI browser authorization remains awaiting owner completion; the latest session (`11B98`) was not completed.
4. Play Console access is unavailable in this browser session; versionCode 9 availability is unconfirmed.
5. Signing keystore/secrets validation and signed AAB build are blocked by items 2 and 4.
6. `flutter analyze` still reports 234 pre-existing findings (0 errors, 2 warnings, 232 info); this fails the fork QA workflow’s Analyze step but test/build/upload still pass.

## 10. Evidence index

- `evidence/emulator-seed.utf8.log` — sanitized Auth/Firestore seed and verification output.
- `evidence/firestore-before-workflows.json` — baseline Firestore snapshot.
- `evidence/firestore-after-launch.json` — post-launch Firestore snapshot (no workflow writes).
- `evidence/apk-install-v2.log` — owner-approved uninstall/reinstall result.
- `evidence/local-launch1.png`, `evidence/local-final-launch.png`, `evidence/ui-launch*.xml`, `evidence/ui-final-*.xml` — launch/ANR evidence.
- `evidence/emulator-run.utf8.log` — sanitized Auth + Firestore emulator startup (no Storage).
- Fork runs: `45614107494`, `45637734491`.
