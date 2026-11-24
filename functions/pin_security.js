import { randomBytes, scryptSync, timingSafeEqual } from "node:crypto";

const KEY_LENGTH = 64;
const SCRYPT_OPTIONS = { N: 16384, r: 8, p: 1, maxmem: 64 * 1024 * 1024 };

export function validPin(value) {
  return typeof value === "string" && /^\d{6}$/.test(value);
}

export function hashPin(pin, salt = randomBytes(16)) {
  if (!validPin(pin)) throw new TypeError("PIN must contain exactly six digits");
  const derived = scryptSync(pin, salt, KEY_LENGTH, SCRYPT_OPTIONS);
  return { pinSalt: salt.toString("base64"), pinHash: derived.toString("base64") };
}

export function verifyPin(pin, account) {
  if (!validPin(pin) || !account?.pinHash || !account?.pinSalt) return false;
  try {
    const salt = Buffer.from(account.pinSalt, "base64");
    const expected = Buffer.from(account.pinHash, "base64");
    if (salt.length !== 16 || expected.length !== KEY_LENGTH) return false;
    const actual = scryptSync(pin, salt, KEY_LENGTH, SCRYPT_OPTIONS);
    return timingSafeEqual(expected, actual);
  } catch {
    return false;
  }
}

export function nextPinFailure(currentAttempts, now = Date.now()) {
  const attempts = Math.max(0, Number(currentAttempts) || 0) + 1;
  if (attempts >= 5) return { pinAttempts: 0, pinLockedUntil: now + 15 * 60 * 1000, locked: true };
  return { pinAttempts: attempts, pinLockedUntil: 0, locked: false };
}
