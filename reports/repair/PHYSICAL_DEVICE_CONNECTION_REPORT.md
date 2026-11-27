# Sangaso physical-device QA — connection and auth repair report

Date: 2026-11-27
Device: HONOR WDY-LX2 (HNWDY-M), Android 14 / SDK 34
Wi-Fi ADB serial used for every command: `adb-A4SFCP3B17401242-f6P7kg._adb-tls-connect._tcp`
Backend: local Firebase emulators only, project `demo-sangaso-local`
Branch: `fix/sangaso-full-repair-2026-11-22`

## Summary

Overall readiness: **NOT READY — CRITICAL DEFECTS REMAIN**.

The original auth defect was diagnosed and the transport-blocker fixed. The app now reaches the local Auth and Firestore emulators from the physical device. Final signed-in UI confirmation and booking workflows are still blocked because the device dropped from Wi-Fi ADB after the successful emulator requests.

No production Firebase write, website deploy, Play Console upload, or production booking test was performed.

## Results

| Check | Status | Evidence / notes |
| --- | --- | --- |
| Wi-Fi ADB pairing and exact serial | PASS (earlier), BLOCKED (current) | Device was online and all commands used the exact serial. It is currently not discovered by `adb devices` or `adb mdns services`. |
| Reverse forwarding `9099`/`8080` | PASS | Direct mappings were restored after each proxy run. Device-side `curl` to the Auth emulator returned HTTP 200. |
| Local Auth + Firestore emulators | PASS | Ports `9099`, `8080`, `4000`, `4400` listening. Seed verification: 2 users, 3 services. |
| Original CI APK emulator targeting | FAIL | Proxy inserted between device and host logged zero app connections; sign-in showed `Sign-in is unavailable right now (unknown).` |
| Local rebuild with explicit defines | PASS | APK `C53004C6C4A62E0A5513E41EC608486F39080A26CB8C407AE3E88041FDCDB64F`; defines included `SANGASO_USE_EMULATORS=true` and `SANGASO_EMULATOR_HOST=127.0.0.1` in `kernel_blob.bin`. |
| Cleartext fix | PASS | Debug-only network security config permits cleartext for `localhost`, `127.0.0.1`, `10.0.2.2`. Release builds do not merge it. Present in installed APK manifest. |
| Auth emulator reachability from app | PASS | Proxy logged `POST /www.googleapis.com/identitytoolkit/v3/relyingparty/verifyPassword?...` at `2026-11-27T16:29:28.623Z`. |
| Firestore emulator reachability from app | PASS | Proxy logged a connection at `2026-11-27T16:29:31.603Z` beginning with `PRI * HTTP/2`. |
| Seeker sign-in final UI state | BLOCKED | App left foreground after sign-in; explicit relaunch showed a blank Flutter view. Device then dropped from ADB before final confirmation. |
| Firestore state before/after sign-in | PASS (no unexpected writes) | `physical-baseline-v3.json` and `physical-after-v7-seeker-signin.json` contain the same 2 users, 3 services, 0 bookings, 0 notifications; only capture timestamp differs. |
| Booking create/read/update/cancel | NOT TESTED | Held pending confirmed signed-in UI state. |
| Provider sign-in | NOT TESTED | Held pending seeker flow completion. |
| ANR investigation | PARTIAL BLOCKED | Earlier ANRs captured; no new ANR trace after the cleartext fix before disconnect. |
| Upstream workflow run / live Firebase rules | BLOCKED | GitHub workflow scope and Firebase login not approved. |
| Play Console versionCode 9 / signed AAB | BLOCKED | Play Console unauthenticated; signing assets not validated. |

## Root cause

The app was built with the correct emulator defines, but Android 14 blocked the HTTP calls the Firebase SDKs make to the local emulators. The debug manifest had no cleartext exception. Device-side `curl` succeeded because shell traffic is not subject to the app's network-security policy.

Fix: `android/app/src/debug/res/xml/network_security_config.xml` keeps cleartext disabled by default and permits it only for local emulator hosts. `android/app/src/debug/AndroidManifest.xml` references it in the debug source set.

## Next move

1. Restore Wi-Fi debugging and rediscover the device serial.
2. Bring Sangaso to the foreground and confirm the signed-in route/UI.
3. If the blank view persists, capture a bounded logcat/ANR trace before any further input.
4. Resume one booking operation at a time with before/after Firestore snapshots.
5. Commit/push the repair changes to the fork repair branch only.

## Evidence files

- `AUTH_EMULATOR_AUDIT.md`
- `v7-auth-proxy.log`, `v7-firestore-proxy.log`
- `ui-v7-before-signin.xml`, `ui-v7-signin-1s.xml`, `ui-v7-after-signin.xml`
- `ui-v7-explicit-start-retry.xml`
- `physical-baseline-v3.json`, `physical-after-v7-seeker-signin.json`
- `physical-v4-stream-install.log`, `local-qa-apk-build-cleartext-fix.log`
