# P0 Foundation Verification — 2026-11-27

Scope: local source, emulator, and CI-gate work only. No Firebase deploy, website deploy,
Play Console upload, live booking test, or production rules/index change was performed.

## Results

| Area | Status | Evidence |
| --- | --- | --- |
| Flutter unit/widget tests | PASS | `flutter test` from `app/` — 104 tests passed. |
| Flutter analyzer | FAIL (non-gating) | 233 pre-existing info/warning findings; no new errors in changed files. Not used as a P0 gate. |
| Trusted backend build | PASS | `npm run build` in `app/functions` — TypeScript compiled cleanly. |
| Firestore rules red-team tests | PASS | `npm run test:emulator` in `app/rules-tests` — 12/12 passed against `demo-sangaso-rules`. |
| JavaScript syntax checks | PASS | `node --check` passed for `rules-tests/firestore.rules.test.js` and `local-test/seed.js`. |
| Patch hygiene | PASS | `git diff --check` clean (line-ending warnings only). |
| CI workflow hardening | PASS in source | QA triggers broadened, failed-gate APK upload removed, shell injection removed, signing secret guard added, artifact checks set to `error`, timeouts added, dedicated security-gates workflow added. |
| Physical-device QA | BLOCKED | HONOR device absent from `adb devices` / `adb mdns services`; no signed-in UI or booking workflow re-run. |
| Live Firebase rules/index verification | BLOCKED | Firebase CLI unauthenticated; live project state not read or changed. |
| Play Console readiness | BLOCKED | Unauthenticated; versionCode and signing assets unconfirmed. |
| Storage emulator rules tests | NOT TESTED | Storage rules written but not exercised in emulator. |
| Functions emulator integration | NOT TESTED | Functions source compiles; triggers not run end-to-end. |
| Production notification ownership | NOT TESTED | Clients still write `notifications` directly; migration is P1 before rules deploy. |
| Provider profile reads | NOT TESTED | Clients still read `users/{uid}` for provider discovery; migration is P1 before rules deploy. |

## Security architecture added

- Source-controlled `firebase.json`, `firestore.rules`, `storage.rules`, and `firestore.indexes.json`.
- Trusted backend source in `functions/` for admin claims, public-profile projection, and
  backend-owned notifications. Source only; not deployed.
- Admin authority is based on the Firebase Auth `admin` custom claim, never a user-document field.
- `publicProfiles/{uid}` is the non-PII read projection; `users/{uid}` remains self/admin-only.
- Red-team rules tests cover unauthenticated reads, cross-user PII access, role escalation,
  service takeover, booking participant boundaries, chat participant boundaries, forged
  notifications, oversized fields, admin moderation, and public-profile reads.

## Dependency footprint notes

- `functions`: install completed; npm reported 9 moderate advisories.
- `rules-tests`: install completed; npm reported 19 advisories (14 moderate, 5 high), all in
  test/tooling dependencies (`firebase-tools` and transitive packages).
- Production-only audit commands timed out in this environment; no advisory was auto-fixed.

## Important limitations

These rules remain a **prototype until reviewed against live data shapes and migrated clients**.
Do not deploy them to a live Firebase project before completing P1 migrations and an explicit
owner-approved rollout. No emulator-only rule variant is included for deployment.
