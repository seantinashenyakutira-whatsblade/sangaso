# Sangaso trusted backend (source only)

This package is the lasting home for privileged operations. It has **not** been deployed in this repair pass.

## Why it exists

- `setUserClaims` is the only supported way to grant the `admin` claim or change KYC/ban/suspension state. Firestore rules read `request.auth.token.admin`, never a user-document field.
- Firestore triggers create notifications. Clients must stop writing `notifications` directly before these rules are deployed.
- `syncPublicProfile` maintains a non-PII `publicProfiles/{uid}` projection so user documents containing email/phone/address stay private.

## Required migration before production rules are enabled

1. Deploy these functions with Admin SDK credentials (owner approval required).
2. Bootstrap one admin claim out of band:
   - `functions setUserClaims` is callable only by an existing admin, so the first admin must be set with an Admin SDK script or Firebase console custom-claims workflow.
   - Do not paste credentials or tokens into chat.
3. Update Flutter and website notification writers to stop creating `notifications` directly; rely on these triggers.
4. Update provider-profile reads to use `publicProfiles/{uid}` instead of `users/{uid}`.
5. Normalize all Firestore timestamps to `timestamp` values (see `firestore.rules`).

## Local verification

```
cd app/functions
npm install
npm run build
```

The root `app/firebase.json` starts Auth, Functions, Firestore, Storage and UI emulators when the owner explicitly approves emulator QA.
