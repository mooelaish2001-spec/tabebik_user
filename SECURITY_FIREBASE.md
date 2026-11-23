# Firebase security baseline — Tabebik

## Status
This is a fail-closed security baseline, not a declaration that the apps are production-ready.
Do not deploy medical-data access until the migration and emulator tests below pass.

## Trusted identity contract
Only a trusted Admin SDK backend may set Firebase custom claims:
- patient: { role: "patient" }
- doctor: { role: "doctor", doctorLic: "<verified doctor license>" }
- center manager: { role: "center_manager", centerId: "<approved center id>" }
- center reception: { role: "center_reception", centerId: "<approved center id>" }
- platform administrator: { platformAdmin: true }

Never derive roles or center membership from a client-written Firestore field or an unverified phone number.
Do not let clients set custom claims.

## Why bookings and patient documents are temporarily closed
The current booking model places operational booking fields and health/complaint fields in the same Firestore document (including health fields spread from the patient's health profile). Firestore Security Rules cannot redact individual fields from a document. Granting a center read access to that document would expose the medical fields too. The current users document also mixes profile and health data.
Consequently, client access to users, bookings, booking private subcollections, encounters, medicalRecords and followUps is denied until the schema is split and migrated.

## Required target data model
- users/{uid}: non-medical profile only.
- patients/{uid}/medical/{recordId}: medical data; patient-controlled access.
- bookings/{bookingId}: operational fields only (patientUid, centerId, doctorLic, service type, schedule, price, status, receipt metadata).
- bookings/{bookingId}/private/{recordId}: medical details, complaint, history and files metadata.
- patientDoctorGrants/{uid}_{doctorUid}: explicit, revocable patient grant with patientUid, doctorUid, bookingId, active, grantedAt, revokedAt.
- centerMembers/{memberUid}: server-managed membership keyed by Firebase UID, not phone number.
- doctors/{doctorLic}: public directory only; verification set by trusted backend.
- encounters/{id} and followUps/{id}: server-managed linkage to patientUid and doctorUid plus explicit grant.
- medical files: Storage medical/{patientUid}/{recordId}/{fileId}; encrypt client-side before upload and store only ciphertext.

## Encryption requirements
Firebase transport encryption and at-rest encryption are platform protections, not end-to-end encryption. Before storing real medical data:
- encrypt on the client using authenticated encryption (AES-256-GCM or an equivalent vetted AEAD);
- use a fresh random nonce for every encryption under a key;
- use a random per-record/file data key; wrap it with a managed key-encryption key;
- keep wrapping keys in KMS/Secret Manager or a dedicated key-management service, never in the Flutter source, Firestore, or remote config;
- define device recovery, multi-device access, doctor key sharing, revocation and key rotation;
- never log plaintext, keys, tokens, medical file URLs or medical payloads.

## Deployment gates
1. Migrate the mixed booking/user schema; remove health fields from operational booking documents.
2. Provision and test custom claims from a trusted backend.
3. Implement patient consent and doctor-to-booking assignment records.
4. Write allow rules for the separated schema and storage paths.
5. Add Firebase Emulator tests for unauthenticated, patient owner, assigned doctor, unrelated doctor, center manager, reception and admin.
6. Deploy only after all tests pass and a security review confirms no cross-role reads/writes.


## 2026-11 backend integration stage
- Patient booking creation now uses the `createPatientBooking` callable. The server rejects unknown/medical fields, sets `patientUid` from Firebase Auth, and checks the approved center and verified doctor membership before creating a doctor booking.
- The patient app uses `listPatientBookings` to refresh booking status and `listPatientFollowUps` to show linked in-person visits. These responses contain operational metadata only.
- Encounter-code redemption is tied to the same Firebase UID that owns the booking. The doctor-side callable checks the verified doctor profile UID, recorded attendance and completed visit; the raw six-digit code is not stored in Firestore.
- Patient Firebase Auth is currently anonymous. The typed phone number is not verified; the anonymous UID is the booking owner and may be lost if app data is cleared or the app is reinstalled.
- The doctor repository does not currently contain a checked-in Firebase project binding/config file, so the project used by its Functions must be confirmed to match the patient app's configured project before deployment.
- Firestore and Storage rules remain fail-closed. Functions source has not been deployed. App Check, the `ENCOUNTER_CODE_PEPPER` secret and trusted doctor claims must be provisioned before live tests.
- The follow-up screen currently lists the linked visit only. Clinical exam/treatment data, patient uploads, medical-record consent, encrypted storage and key management are not implemented as live services.
- Do not store real medical data or loosen rules until schema migration, consent lifecycle, encryption/key management, Firebase Emulator authorization tests and a security review are complete.
