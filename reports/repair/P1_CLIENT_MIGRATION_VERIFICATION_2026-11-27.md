# P1 Client Migration Verification — 2026-11-27

Scope: local source, emulator, and CI-gate work only. No Firebase deploy, website deploy,
Play Console upload, live booking test, production rules/index change, or production data
write was performed.

## Results

| Area | Status | Evidence |
| --- | --- | --- |
| Provider discovery migration | PASS | Booking, provider-profile, and service-details screens now read `publicProfiles/{uid}` through the new non-PII `PublicProfileModel`; `bio` is included in the projection. |
| Client notification ownership removal | PASS in source | `NotificationService` is read/mark-only; booking, messaging, `main.dart`, and the mock service no longer create notifications. Unit tests assert no client-owned notification writes. |
| Booking write hardening | PASS | `BookingModel.toMap()` omits null optional fields; new bookings omit provider/seeker email and phone; status updates add `updatedAt`; tests cover non-PII payloads, discoverability, idempotency, and status transitions. |
| Messaging write hardening | PASS | `MessageModel` stamps `receiverId`, omits duplicated `id` and null `imageUrl`, and falls back to the document ID when read; tests cover sender/receiver stamping and participant rejection. |
| Firestore rules hardening | PASS | Path helpers moved into the `database` match scope; message create requires `receiverId` to be the other booking participant; `imageUrl` is validated. |
| Flutter unit/widget tests | PASS | `flutter test` from `app/` — 109/109 passed. |
| Firestore rules red-team tests | PASS | `npm run test:emulator` in `app/rules-tests` — 17/17 passed against `demo-sangaso-rules`, Firestore emulator port `8088`, JDK 21. |
| Trusted backend build | PASS | `npm run build` in `app/functions` — TypeScript compiled cleanly. |
| Flutter analyzer | FAIL (non-gating) | 233 pre-existing info/warning findings; 0 errors. `rules-tests/node_modules/**` is excluded from analysis so generated Dart templates no longer inject unrelated errors. Not used as a P1 gate. |
| JavaScript syntax checks | PASS | `node --check` passed for `rules-tests/firestore.rules.test.js` and `local-test/seed.js`. |
| JSON configuration checks | PASS | Parsed `firebase.json`, `firebase.rules-tests.json`, `firestore.indexes.json`, `functions/package.json`, `functions/tsconfig.json`, and `rules-tests/package.json`. |
| Patch hygiene | PASS | `git diff --check` clean. |
| Local seed harness | NOT TESTED | `local-test/seed.js` now seeds and verifies two `publicProfiles` docs with no `email`, `phoneNumber`, or `address`; full Auth + Firestore emulator seed rerun was not executed in this batch. |
| Functions emulator integration | NOT TESTED | Functions source compiles; triggers were not run end-to-end in the emulator. |
| Production notification ownership | NOT TESTED | Clients no longer write notifications, but backend triggers are source-only and not deployed. |
| Device/live provider and booking flows | NOT TESTED | No `publicProfiles` read or booking flow was exercised on a device against live data shapes. |
| Physical-device QA | BLOCKED | HONOR device absent from `adb devices` / `adb mdns services`; prior Wi-Fi ADB serial must be rediscovered before use. |
| Live Firebase rules/index verification | BLOCKED | Firebase CLI unauthenticated; live project state not read or changed. |
| Play Console readiness | BLOCKED | Unauthenticated; versionCode and signing assets unconfirmed. |
| Website endpoint hardening | NOT TESTED | Deferred; not started in this batch. |
| Storage emulator rules tests | NOT TESTED | Storage rules written but not exercised in emulator. |

## Security changes completed

- Added `PublicProfileModel` as a non-PII discovery read model with no write map.
- Migrated provider discovery reads away from `users/{uid}` to `publicProfiles/{uid}`.
- Added `bio` to the trusted `syncPublicProfile` backend projection and aligned the
  message notification type with the client enum (`newMessage`).
- Removed every client-side notification creation path; the client API is now read/mark-only.
- Removed duplicated provider/seeker contact data from new booking payloads.
- Added strict message recipient stamping and matching rules validation to prevent spoofed
  notification targets.
- Fixed Firestore path-helper scope that previously caused valid booking/chat rules to
  evaluate with a `Null value error`.
- Updated rules tests, service tests, and the local seed harness for the new authority model.

## Important limitations

The rules remain a **prototype until reviewed against live data shapes and released through
an owner-approved rollout**. These results are local-only. Overall readiness remains
**NOT READY — CRITICAL DEFECTS REMAIN** until P2/device QA, live rules/index verification,
CI upstream, and release prerequisites are cleared.
