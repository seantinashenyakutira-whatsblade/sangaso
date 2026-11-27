# Sangaso Firestore rules tests

These tests load `../firestore.rules` into a local Firestore emulator and exercise the
authority boundaries as a hostile client.

## Run

Requires JDK 21+ for current `firebase-tools` emulator versions.

```powershell
$env:JAVA_HOME = 'C:\tools\jdk21\jdk-21.0.12.1+1'
$env:PATH = "$env:JAVA_HOME\bin;$env:PATH"
npm install
npm run test:emulator
```

The test config (`../firebase.rules-tests.json`) uses `demo-sangaso-rules` and port `8088`, so it does not touch the
`demo-sangaso-local` emulator on port `8080` or any live Firebase project. No credentials
are required and no deploy target is configured.

`FIRESTORE_EMULATOR_PORT` can be set if the test harness must use another port.
