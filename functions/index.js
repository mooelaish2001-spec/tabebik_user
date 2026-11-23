import { randomUUID, createHash } from "node:crypto";
import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";
import { onRequest } from "firebase-functions/v2/https";
import {
  generateRegistrationOptions,
  verifyRegistrationResponse,
  generateAuthenticationOptions,
  verifyAuthenticationResponse,
} from "@simplewebauthn/server";

initializeApp();
const db = getFirestore();
const auth = getAuth();

// Keep these values aligned with public/.well-known/assetlinks.json.
const RP_NAME = "طبيبك";
const RP_ID = "tabibek-2f25e.web.app";
const ORIGIN = "https://tabibek-2f25e.web.app";
// Android native WebAuthn origin: base64url(SHA-256 signing-certificate bytes).
const ANDROID_ORIGIN = "android:apk-key-hash:D2CHqKEuCwIW-pdnnUc03LM0u-4pDhHp7RZeMO0gFS4";
const EXPECTED_ORIGINS = [ORIGIN, ANDROID_ORIGIN];
const REGION = "us-central1";
const CHALLENGE_TTL_MS = 5 * 60 * 1000;
const ALLOWED_APPS = new Set(["tabebik_user", "tabebik_center", "tabebik_doctor"]);
const ALLOWED_ORIGINS = new Set([ORIGIN, "https://tabibek-2f25e.firebaseapp.com"]);

function send(res, status, body) {
  res.status(status).set("Cache-Control", "no-store").json(body);
}

function cors(req, res) {
  const origin = req.get("origin");
  if (origin && ALLOWED_ORIGINS.has(origin)) {
    res.set("Access-Control-Allow-Origin", origin);
    res.set("Vary", "Origin");
  }
  res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
  res.set("Access-Control-Allow-Headers", "Content-Type");
  res.set("Access-Control-Max-Age", "3600");
  if (req.method === "OPTIONS") {
    res.status(204).send("");
    return true;
  }
  return false;
}

function validPost(req, res) {
  if (cors(req, res)) return false;
  if (req.method !== "POST") {
    send(res, 405, { error: "method-not-allowed" });
    return false;
  }
  if (!req.is("application/json")) {
    send(res, 415, { error: "json-required" });
    return false;
  }
  if (Buffer.byteLength(JSON.stringify(req.body ?? {}), "utf8") > 64 * 1024) {
    send(res, 413, { error: "request-too-large" });
    return false;
  }
  return true;
}

function getApp(req) {
  const app = String(req.body?.app ?? "");
  return ALLOWED_APPS.has(app) ? app : null;
}

function clientKey(req) {
  // Use the platform-normalized client IP; do not trust a caller-supplied
  // X-Forwarded-For value as the sole rate-limit identity.
  const ip = String(req.ip ?? "unknown");
  return createHash("sha256").update(ip).digest("hex");
}

async function rateLimit(req, action, max, windowMs) {
  const id = createHash("sha256").update(action + ":" + clientKey(req)).digest("hex");
  const ref = db.collection("passkeyRateLimits").doc(id);
  const now = Date.now();
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.data();
    const start = Number(data?.windowStart ?? 0);
    const count = start > now - windowMs ? Number(data?.count ?? 0) : 0;
    if (count >= max) return false;
    tx.set(ref, { windowStart: start > now - windowMs ? start : now, count: count + 1, expiresAt: Timestamp.fromMillis(now + windowMs * 2) });
    return true;
  });
}

function assertPayload(value, max = 100) {
  return typeof value === "string" && value.trim().length > 0 && value.length <= max;
}

async function saveChallenge({ challenge, uid, type, app, displayName = "", phone = "", professionalId = "" }) {
  const ref = db.collection("passkeyChallenges").doc(challenge);
  await ref.create({
    challenge, uid, type, app, displayName, phone, professionalId,
    createdAt: FieldValue.serverTimestamp(),
    expiresAt: Timestamp.fromMillis(Date.now() + CHALLENGE_TTL_MS),
    consumed: false,
  });
}

async function consumeChallenge(challenge, type, app) {
  const ref = db.collection("passkeyChallenges").doc(challenge);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) return null;
    const data = snap.data();
    if (data.type !== type || data.app !== app || data.consumed === true) return null;
    if (data.expiresAt.toMillis() < Date.now()) {
      tx.delete(ref);
      return null;
    }
    tx.update(ref, { consumed: true, consumedAt: FieldValue.serverTimestamp() });
    return data;
  });
}

export const passkeyRegisterOptions = onRequest({ region: REGION, cors: false, maxInstances: 20 }, async (req, res) => {
  try {
    if (!validPost(req, res)) return;
    const app = getApp(req);
    const displayName = String(req.body?.displayName ?? "").trim();
    const phone = String(req.body?.phone ?? "").trim();
    const professionalId = String(req.body?.professionalId ?? "").trim();
    if (!app || !assertPayload(displayName, 80)) return send(res, 400, { error: "invalid-registration-data" });
    if (app !== "tabebik_user" && !assertPayload(phone, 20)) return send(res, 400, { error: "phone-required" });
    if (app === "tabebik_doctor" && !/^\\d{3,8}$/.test(professionalId)) return send(res, 400, { error: "council-number-required" });
    // Never allow a passkey-only user to take over a pre-existing professional
    // record created by a center. Those claims require a manual identity review.
    if (app === "tabebik_doctor") {
      const [key, doctor] = await Promise.all([
        db.collection("doctorKeys").doc(professionalId).get(),
        db.collection("doctors").doc(professionalId).get(),
      ]);
      if (key.exists || doctor.exists) return send(res, 409, { error: "professional-account-claim-required" });
    }
    if (!(await rateLimit(req, "register", 5, 60 * 60 * 1000))) return send(res, 429, { error: "rate-limited" });

    const uid = randomUUID();
    const options = await generateRegistrationOptions({
      rpName: RP_NAME,
      rpID: RP_ID,
      userID: Buffer.from(uid, "utf8"),
      userName: uid,
      userDisplayName: displayName,
      attestationType: "none",
      supportedAlgorithmIDs: [-7, -257],
      authenticatorSelection: {
        residentKey: "required",
        userVerification: "required",
        authenticatorAttachment: "platform",
      },
      timeout: CHALLENGE_TTL_MS,
    });
    await saveChallenge({ challenge: options.challenge, uid, type: "registration", app, displayName, phone, professionalId });
    return send(res, 200, { uid, options });
  } catch (error) {
    console.error("passkeyRegisterOptions failed", error);
    return send(res, 500, { error: "passkey-registration-unavailable" });
  }
});

export const passkeyRegisterVerify = onRequest({ region: REGION, cors: false, maxInstances: 20 }, async (req, res) => {
  try {
    if (!validPost(req, res)) return;
    const app = getApp(req);
    const response = req.body?.credential;
    const challenge = String(req.body?.challenge ?? "");
    if (app !== "tabebik_user" || !assertPayload(challenge, 200) || !response || !assertPayload(response.id, 2048)) {
      return send(res, 400, { error: "invalid-registration-response" });
    }
    const challengeSnap = await db.collection("passkeyChallenges").doc(challenge).get();
    if (!challengeSnap.exists) return send(res, 400, { error: "challenge-expired" });
    const challengeData = challengeSnap.data();
    if (challengeData.type !== "registration" || challengeData.app !== app || challengeData.consumed || challengeData.expiresAt.toMillis() < Date.now()) {
      return send(res, 400, { error: "challenge-expired" });
    }
    if (!(await rateLimit(req, "register-verify", 10, 60 * 60 * 1000))) return send(res, 429, { error: "rate-limited" });
    const verification = await verifyRegistrationResponse({
      response,
      expectedChallenge: challengeData.challenge,
      expectedOrigin: EXPECTED_ORIGINS,
      expectedRPID: RP_ID,
      requireUserVerification: true,
    });
    if (!verification.verified || !verification.registrationInfo) return send(res, 401, { error: "passkey-verification-failed" });

    const { credential, credentialDeviceType, credentialBackedUp } = verification.registrationInfo;
    const passkeyRef = db.collection("passkeyCredentials").doc(credential.id);
    const accountRef = db.collection("passkeyAccounts").doc(challengeData.uid);
    await db.runTransaction(async (tx) => {
      const [challengeNow, existingCredential, existingAccount] = await Promise.all([
        tx.get(db.collection("passkeyChallenges").doc(challenge)),
        tx.get(passkeyRef),
        tx.get(accountRef),
      ]);
      if (!challengeNow.exists || challengeNow.data().consumed || challengeNow.data().expiresAt.toMillis() < Date.now()) {
        throw new Error("challenge-already-used");
      }
      if (existingCredential.exists || existingAccount.exists) throw new Error("credential-or-account-exists");
      tx.update(db.collection("passkeyChallenges").doc(challenge), { consumed: true, consumedAt: FieldValue.serverTimestamp() });
      tx.create(passkeyRef, {
        uid: challengeData.uid,
        credentialId: credential.id,
        publicKey: Buffer.from(credential.publicKey).toString("base64"),
        counter: credential.counter,
        transports: credential.transports ?? [],
        deviceType: credentialDeviceType,
        backedUp: credentialBackedUp,
        app,
        createdAt: FieldValue.serverTimestamp(),
      });
      tx.create(accountRef, {
        uid: challengeData.uid,
        role: app === "tabebik_user" ? "patient" : app === "tabebik_doctor" ? "doctor" : "center",
        displayName: String(challengeData.displayName ?? "").trim().slice(0, 80),
        phone: String(challengeData.phone ?? ""),
        professionalId: String(challengeData.professionalId ?? ""),
        app,
        status: "active",
        createdAt: FieldValue.serverTimestamp(),
      });
    });

    const displayName = String(challengeData.displayName ?? "").trim().slice(0, 80);
    try {
      await auth.createUser({ uid: challengeData.uid, displayName });
    } catch (error) {
      // Roll back Firestore credential/account records if Firebase Auth creation fails.
      await Promise.all([passkeyRef.delete(), accountRef.delete()]);
      throw error;
    }
    const account = {
      role: app === "tabebik_user" ? "patient" : app === "tabebik_doctor" ? "doctor" : "center",
      phone: String(challengeData.phone ?? ""),
      professionalId: String(challengeData.professionalId ?? ""),
      displayName,
      app,
    };
    const token = await auth.createCustomToken(challengeData.uid, { role: account.role, authMethod: "passkey", accountPhone: account.phone, professionalId: account.professionalId });
    return send(res, 200, { verified: true, uid: challengeData.uid, customToken: token, account });
  } catch (error) {
    console.error("passkeyRegisterVerify failed", error);
    return send(res, 401, { error: "passkey-registration-failed" });
  }
});

export const passkeyLoginOptions = onRequest({ region: REGION, cors: false, maxInstances: 30 }, async (req, res) => {
  try {
    if (!validPost(req, res)) return;
    const app = getApp(req);
    if (!app) return send(res, 400, { error: "invalid-app" });
    if (!(await rateLimit(req, "login", 30, 15 * 60 * 1000))) return send(res, 429, { error: "rate-limited" });
    const options = await generateAuthenticationOptions({
      rpID: RP_ID,
      userVerification: "required",
      timeout: CHALLENGE_TTL_MS,
    });
    await saveChallenge({ challenge: options.challenge, uid: "", type: "authentication", app });
    return send(res, 200, { challenge: options.challenge, options });
  } catch (error) {
    console.error("passkeyLoginOptions failed", error);
    return send(res, 500, { error: "passkey-login-unavailable" });
  }
});

export const passkeyLoginVerify = onRequest({ region: REGION, cors: false, maxInstances: 30 }, async (req, res) => {
  try {
    if (!validPost(req, res)) return;
    const app = getApp(req);
    const challenge = String(req.body?.challenge ?? "");
    const response = req.body?.credential;
    if (!app || !assertPayload(challenge, 200) || !response || !assertPayload(response.id, 2048)) {
      return send(res, 400, { error: "invalid-authentication-response" });
    }
    if (!(await rateLimit(req, "login-verify", 40, 15 * 60 * 1000))) return send(res, 429, { error: "rate-limited" });
    const challengeRef = db.collection("passkeyChallenges").doc(challenge);
    const challengeSnap = await challengeRef.get();
    if (!challengeSnap.exists) return send(res, 401, { error: "challenge-expired" });
    const challengeData = challengeSnap.data();
    if (challengeData.type !== "authentication" || challengeData.app !== app || challengeData.consumed || challengeData.expiresAt.toMillis() < Date.now()) {
      return send(res, 401, { error: "challenge-expired" });
    }

    const matches = await db.collection("passkeyCredentials").where("credentialId", "==", response.id).limit(1).get();
    if (matches.empty) return send(res, 401, { error: "passkey-not-found" });
    const credentialDoc = matches.docs[0];
    const stored = credentialDoc.data();
    if (stored.app !== app) {
      return send(res, 403, { error: "passkey-app-mismatch" });
    }
    const verification = await verifyAuthenticationResponse({
      response,
      expectedChallenge: challengeData.challenge,
      expectedOrigin: ORIGIN,
      expectedRPID: RP_ID,
      credential: {
        id: stored.credentialId,
        publicKey: new Uint8Array(Buffer.from(stored.publicKey, "base64")),
        counter: Number(stored.counter ?? 0),
        transports: stored.transports ?? [],
      },
      requireUserVerification: true,
    });
    if (!verification.verified) return send(res, 401, { error: "passkey-verification-failed" });

    const newCounter = verification.authenticationInfo.newCounter;
    await db.runTransaction(async (tx) => {
      const [challengeNow, credentialNow] = await Promise.all([tx.get(challengeRef), tx.get(credentialDoc.ref)]);
      if (!challengeNow.exists || challengeNow.data().consumed || challengeNow.data().expiresAt.toMillis() < Date.now()) {
        throw new Error("challenge-already-used");
      }
      if (!credentialNow.exists) throw new Error("credential-removed");
      tx.update(challengeRef, { consumed: true, consumedAt: FieldValue.serverTimestamp() });
      tx.update(credentialDoc.ref, { counter: newCounter, lastUsedAt: FieldValue.serverTimestamp() });
    });
    const account = await db.collection("passkeyAccounts").doc(stored.uid).get();
    if (!account.exists || account.data().status !== "active") return send(res, 403, { error: "account-disabled" });
    const token = await auth.createCustomToken(stored.uid, { role: account.data().role, authMethod: "passkey", accountPhone: account.data().phone ?? "", professionalId: account.data().professionalId ?? "" });
    return send(res, 200, {
      verified: true,
      uid: stored.uid,
      customToken: token,
      account: {
        role: account.data().role,
        phone: account.data().phone ?? "",
        professionalId: account.data().professionalId ?? "",
        displayName: account.data().displayName ?? "",
        app: account.data().app,
      },
    });
  } catch (error) {
    console.error("passkeyLoginVerify failed", error);
    return send(res, 401, { error: "passkey-authentication-failed" });
  }
});
