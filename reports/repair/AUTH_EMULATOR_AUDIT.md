# Physical-device Auth emulator audit — 2026-11-27

## Scope

- Device: HONOR WDY-LX2, Android 14, Wi-Fi ADB serial `adb-A4SFCP3B17401242-f6P7kg._adb-tls-connect._tcp`.
- Backend intended for QA: local Firebase emulators only, project `demo-sangaso-local`.
- No production Firebase write or Play upload was performed.

## Observations

1. The corrected CI APK (`sangaso-physical-debug-apk-v2`, SHA-256 `EA41FA…4332`) installed successfully and launched to the Sangaso onboarding screen.
2. `adb reverse` mappings were active and verified with device-side `curl`:
   - `tcp:9099` → host `127.0.0.1:9099` returned HTTP 200 for the emulator root.
   - `tcp:8080` → host `127.0.0.1:8080` was reachable.
   - A direct Auth REST sign-in using the seeded fake account succeeded with HTTP 200 and the expected local UID.
3. Tapping **Get started** opened `/login`; email/password fields accepted the seeded fake credentials (verified in the Accessibility XML).
4. Tapping **Sign In** produced the snackbar `Sign-in is unavailable right now (unknown).` and stayed on `/login`.
5. A localhost TCP-to-HTTP proxy was inserted between the device and host Auth emulator:
   - `adb reverse tcp:9099 tcp:9097`
   - host proxy on `127.0.0.1:9097` forwarding to `127.0.0.1:9099`
   - The proxy logged a device `curl` request correctly, proving the interception worked.
   - After an app force-stop and relaunch with the proxy active, the sign-in attempt produced **zero** proxy log entries.
6. The same proxy check on Firestore port `8080` also produced zero app connections after relaunch.
7. Device `netstat -tn` showed multiple outbound HTTPS connections to Google IP ranges while the app was active, but that alone is not conclusive because other system services are also present.

## Conclusion

The installed CI APK does **not** appear to be reaching the local Auth/Firestore emulators despite the build workflow's `--dart-define` values. The local harness itself is healthy: the emulators, reverse forwarding, seeded users, and device-side HTTP checks all pass. The defect is in the APK/build configuration actually used for physical-device QA, not in device connectivity.

## Fix being applied

Rebuild the debug APK locally with explicit defines and install that build on the HONOR phone:

```
flutter build apk --debug \
  --dart-define=SANGASO_USE_EMULATORS=true \
  --dart-define=SANGASO_EMULATOR_HOST=127.0.0.1
```

After installation, repeat connectivity and auth checks before resuming booking workflows.

The first local rebuild attempt used Android Studio JBR (OpenJDK 25.0.4) and failed during Gradle Kotlin DSL compilation with `java.lang.IllegalArgumentException: 25.0.4`. The retry uses the installed Temurin JDK 17 (`C:\tools\jdk17\jdk-17.0.20.1+1`), matching the Java 17 requirement already added to both GitHub workflow jobs. Flutter was explicitly pointed at that JDK with `flutter config --jdk-dir=...` because Flutter otherwise preferred the Android Studio JBR (Java 25) ahead of `JAVA_HOME`. This Flutter-only setting will be cleared after the QA APK is built.

## Root cause found — cleartext traffic blocked in debug builds

The locally rebuilt v3 APK does contain the correct compile-time values: its `kernel_blob.bin` includes `SANGASO_USE_EMULATORS`, `SANGASO_EMULATOR_HOST`, and `127.0.0.1` in the app constants section. The login form submits correctly (the `unknown` snackbar appears within one second), and the app remains responsive (the **Forgot password?** dialog opens normally). Yet the intercepted Auth and Firestore proxies still recorded zero connections.

The debug `AndroidManifest.xml` had no `android:networkSecurityConfig` and the main manifest did not enable cleartext traffic. Android 14 therefore blocks the HTTP calls the Firebase SDKs make to `http://127.0.0.1:9099` and `http://127.0.0.1:8080` at the application network-policy layer. Device-side `curl` succeeds because the shell is not subject to the app's network security policy, which is why the earlier connectivity checks passed while the app failed.

## Fix applied

A debug-only network security config was added at `android/app/src/debug/res/xml/network_security_config.xml`. It keeps cleartext disabled by default and permits it only for `localhost`, `127.0.0.1`, and `10.0.2.2`. The debug manifest now references it via `android:networkSecurityConfig`. Release builds do not merge this debug source set, so production traffic remains HTTPS-only.

A new APK was rebuilt with the same explicit emulator defines (`C53004C6…B64F`) and installed on the HONOR phone. On the retry, the intercepting proxy recorded an Auth request at `2026-11-27T16:29:28.623Z`:

```
POST /www.googleapis.com/identitytoolkit/v3/relyingparty/verifyPassword?key=fake-api-key-for-local-emulators
```

The Firestore proxy also recorded a connection at `2026-11-27T16:29:31.603Z` (`PRI * HTTP/2` preface). This confirms the cleartext fix restored app-to-emulator traffic. Final UI verification of the signed-in state was interrupted when Wi-Fi ADB disconnected, so post-sign-in navigation remains BLOCKED pending device reconnection.

## Evidence

- `physical-wifi-pm-install.log` — successful `pm install` after push.
- `device-auth-curl-valid.raw` — sanitized direct emulator sign-in response.
- `ui-after-get-started.xml`, `ui-after-seeker-signin-retry.xml` — login screen state.
- `ui-signin-tap-1s.xml` — captures the `unknown` error snackbar.
- `seeker-signin-motionevent-logcat.log` — bounded logcat around the failed sign-in.
