---
id: ADR-0009
title: "ADR-0009: Pluggable OTP Auth (Backend Today, Firebase Now, MSG91 Later)"
summary: "Introduced an OtpProvider strategy on both frontend and backend so login can switch between the existing backend OTP, Firebase phone auth, and a later MSG91 provider via config rather than a rewrite."
type: decision
status: accepted
apps: ["backend","customer"]
module: "auth"
anchors:
  - { repo: customer, path: "src/features/auth/otp/index.ts" }
  - { repo: customer, path: "src/features/auth/otp/types.ts" }
  - { repo: customer, path: "src/features/auth/otp/BackendOtpProvider.ts" }
  - { repo: customer, path: "src/features/auth/otp/FirebaseOtpProvider.ts" }
  - { repo: customer, path: "src/features/auth/otp/session.ts" }
  - { repo: backend, path: "src/main/java/com/example/ninja/controller/AuthController.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/service/impl/AuthServiceImpl.java" }
  - { repo: backend, path: "src/main/java/com/example/ninja/dto/PhoneExistsResponse.java" }
verified_against: "customer:49f04f81d4853953686a33f7e644ed7944749951; backend:ff5ade334891238d16b8010e372fdbbc502c193e"
updated: 2026-06-22
---

# ADR-0009: Pluggable OTP Auth (Backend Today, Firebase Now, MSG91 Later)

## Context

OTP login/signup already existed end-to-end, backend-owned: `/auth/send-otp` + `/auth/verify-otp`
issue the app JWT, with a hardcoded dev OTP (`"1234"`) and no real SMS gateway. The product need
was real SMS delivery via Firebase Phone Auth immediately, with MSG91 as a later option once its
DLT registration clears. The alternative on the table was wiring Firebase directly into the
existing screens/services — rejected because it would tightly couple the auth flow to one
provider and make switching (or adding MSG91 later) a rewrite rather than a config change.

## Decision

Introduce an `OtpProvider` strategy on both sides. Every provider reduces to the same contract —
*prove phone ownership → return our JWT* — so screens stay provider-agnostic.

- **Frontend** (`src/features/auth/otp/`): an `OtpProvider` interface (`codeLength`, `sendCode`,
  `confirmCode`), a `BackendOtpProvider` wrapping the existing service, and `getOtpProvider()`
  switched by `APP_CONFIG.OTP_PROVIDER` (defaults to `backend`). An in-memory `session.ts` holds
  the active session across login → verify, because the Firebase confirmation object is not
  serializable and can't travel through router params. Screens (`login.tsx`, `verify.tsx`) call
  only `getOtpProvider()` and never branch on which provider is active.
- **Backend**: `/auth/send-otp` + `/auth/verify-otp` stay in place (dormant path for MSG91 later).
  Added `GET /auth/exists?phone=` (pre-check before triggering an SMS) and
  `POST /auth/firebase-login { idToken }`, which verifies the token via the Firebase Admin SDK and
  reuses a single shared `finalizeLoginAndIssueJwt()` extracted from the existing verify-OTP path
  (activate user + consume invites + issue JWT) — one issuance path for every provider, so
  behaviour can't drift between them.

Risks reviewed and resolved before implementation:
- **4-digit UI vs 6-digit Firebase codes** — the code-entry UI reads box count from
  `provider.codeLength` rather than hardcoding 4.
- **Firebase sends a real SMS to any number** — `GET /auth/exists` gates the call so an unknown
  number on login doesn't waste an SMS; signup stays a separate flow (it still needs name/email).
- **`@react-native-firebase/auth` is a native module** — not available in Expo Go; requires an
  `eas build --profile development` dev client before the Firebase path can be exercised.
- **Backend must not trust client claims** — `/auth/firebase-login` verifies the ID token
  signature/audience/expiry server-side via Firebase Admin before issuing a JWT.

## Consequences

- Switching the active OTP provider (or adding MSG91 once DLT clears) is a config change
  (`OTP_PROVIDER` / `APP_CONFIG.OTP_PROVIDER`), not a rewrite of login/verify screens.
- Firebase Admin was already wired into the backend for FCM push (`firebase-admin` dependency,
  `FirebaseConfig`, gitignored service-account key, `app.firebase.enabled=true`), so ID-token
  verification reuses that existing setup — no new key, dependency, or config was needed.
- The Firebase provider cannot be tested in Expo Go; any change to that path requires a dev
  build, which slows iteration on that provider specifically (the backend provider is unaffected).
- Session state for an in-flight OTP confirmation lives in memory (`session.ts`), not in
  navigation params or persisted storage — an app kill mid-verification loses the session by
  design and the user must restart the flow.
- `OTP_PROVIDER` defaulting to `backend` means this change ships with zero behaviour change until
  explicitly flipped per environment.

## Enforced in

- Frontend: `src/features/auth/otp/index.ts` (`getOtpProvider()` switch), `types.ts` (the
  `OtpProvider` contract), `BackendOtpProvider.ts`, `FirebaseOtpProvider.ts`, `session.ts`
  (in-memory session across login → verify), and `constants/config.ts` (`APP_CONFIG.OTP_PROVIDER`).
- Backend: `AuthController.java` (`GET /auth/exists`, `POST /auth/firebase-login`),
  `AuthServiceImpl.java` (`finalizeLoginAndIssueJwt()` shared by verify-OTP and Firebase login),
  `PhoneExistsResponse.java`.

---
*Immutable once accepted. If this decision changes, write a new ADR and mark this one `status: superseded` with a link forward.*
