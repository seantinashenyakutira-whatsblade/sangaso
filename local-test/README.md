# Sangaso local emulator test harness

Isolated, opt-in Firebase emulator environment for local Android QA.
Project is hard-pinned to `demo-sangaso-local`. Production Firebase is never
contacted by this folder: `firebase.json` deliberately has **no deploy targets**,
and the seed/verify scripts reject any endpoint other than loopback.

## Fixed parameters

- Project: `demo-sangaso-local`
- Auth emulator: `127.0.0.1:9099`
- Firestore emulator: `127.0.0.1:8080`
- Emulator UI (loopback only): http://127.0.0.1:4000
- Storage emulator is **not** started or configured; add it only if a test requires it.

## Requirements

Reuse the existing tooling. Verified on this PC: Node v22.23.2, Firebase CLI
15.34.0, Temurin JDK 21.0.12 (emulator shell only). Android/Gradle builds use
JDK 17. Do not install another Android SDK or system image.

## Local fake credentials (untracked)

Create `local-test/fake-credentials.local.json` in this folder. It is ignored by
Git and must never be committed. Only `@demo-sangaso-local.test` addresses are
accepted by the seed script.

```json
{
  "seeker": {
    "email": "seeker@demo-sangaso-local.test",
    "password": "<local-only-password>"
  },
  "provider": {
    "email": "provider@demo-sangaso-local.test",
    "password": "<local-only-password>"
  }
}
```

Use a different path via `SANGASO_FAKE_CREDENTIALS_FILE` if preferred.

## Start and seed

```powershell
cd C:\Users\MRSEANNYAKUTIRA\Desktop\Sangaso\app\local-test
firebase emulators:start --project demo-sangaso-local --only auth,firestore
```

In a second terminal:

```powershell
cd C:\Users\MRSEANNYAKUTIRA\Desktop\Sangaso\app\local-test
node seed.js
```

The seed now:

- creates/updates both Auth Emulator accounts and sets `emailVerified: true`;
- verifies both passwords through the Auth Emulator REST API;
- writes `/users/{actualAuthUid}` documents;
- sets every seeded service `providerId` to the actual provider UID;
- writes ignored `seed-state.json` with the resolved UIDs (no passwords).

Capture Firestore snapshots before and after each workflow:

```powershell
node verify.js C:\Users\MRSEANNYAKUTIRA\Desktop\Sangaso\app\reports\qa\evidence\before.json
node verify.js C:\Users\MRSEANNYAKUTIRA\Desktop\Sangaso\app\reports\qa\evidence\after.json
```

## Run the Android app against the emulators

Android emulator (`emulator-5554`) must reach the Windows host at `10.0.2.2`:

```powershell
flutter run -d emulator-5554 ^
  --dart-define=SANGASO_USE_EMULATORS=true ^
  --dart-define=SANGASO_EMULATOR_HOST=10.0.2.2
```

PowerShell equivalent:

```powershell
$env:SANGASO_USE_EMULATORS='true'
$env:SANGASO_EMULATOR_HOST='10.0.2.2'
flutter run -d emulator-5554
```

Desktop and web keep `localhost` by default:

```powershell
flutter run -d windows --dart-define=SANGASO_USE_EMULATORS=true
flutter run -d chrome --dart-define=SANGASO_USE_EMULATORS=true
```

`SANGASO_EMULATOR_HOST` (environment variable or `--dart-define`) overrides the
default. It accepts a bare host or an `http://` URL. In emulator mode the app
also initializes Firebase with `projectId: demo-sangaso-local` and fake app
metadata, so documents match this seed. All emulator calls remain inside the
explicit `SANGASO_USE_EMULATORS` branch; with the flag unset the app uses its
normal production Firebase configuration unchanged.

## Rules safety

`firestore.rules.emulator` and `storage.rules.emulator` are intentionally
permissive, local-only files. They are untracked and ignored. The emulator runs
with its built-in local allow-all behaviour because no rule paths are present in
`firebase.json`. **Never deploy these files and never copy them into a
deployable Firebase configuration.**
