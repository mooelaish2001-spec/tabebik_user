# Tabebik Passkey backend (staged)

This Firebase Functions v2 backend implements WebAuthn ceremonies with
`@simplewebauthn/server`, stores public credential material in Firestore,
and issues Firebase Custom Tokens only after server-side verification.

## Relying party

- RP ID: `tabibek-2f25e.web.app`
- Origin: `https://tabibek-2f25e.web.app`
- Digital Asset Links: `/public/.well-known/assetlinks.json`

The Hosting site and Digital Asset Links file must be deployed and verified
before enabling the client flow. Never change RP ID after passkeys are enrolled.

## Endpoints

- `passkeyRegisterOptions` — patient, center manager/staff, and new doctor identity registration
- `passkeyRegisterVerify` — verify credential, enforce app identity uniqueness, and issue Firebase custom token
- `passkeyLoginOptions` — discoverable passkey challenge
- `passkeyLoginVerify` — verify assertion and issue Firebase custom token

All requests are JSON POSTs. Registration currently allows only the patient
app. Doctor and center onboarding are intentionally rejected until their
professional licence / center approval flows are connected to a trusted
server-side identity. Do not remove their existing sign-in screens until
those flows are implemented.

## Deploy

From the repository root, after reviewing and testing:

```sh
firebase deploy --only functions,hosting
```

The project alias is configured in `.firebaserc`. Deploying is a separate
operator action; commits do not deploy functions or hosting.

## Security notes

- Challenges expire after five minutes and are single-use.
- User verification is required for both ceremonies.
- Credential public keys and counters are stored server-side; private keys
  remain with the platform authenticator.
- Rate limiting is applied by source IP.
- PIN is not part of remote authentication. If added, it should be a local
  app lock protected by platform secure storage and device authentication.
- Configure Firestore TTL for `passkeyChallenges.expiresAt` and
  `passkeyRateLimits.expiresAt` to clean up expired documents.
