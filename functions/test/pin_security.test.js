import test from "node:test";
import assert from "node:assert/strict";
import { hashPin, verifyPin, validPin, nextPinFailure } from "../pin_security.js";

test("PIN accepts exactly six ASCII digits", () => {
  assert.equal(validPin("123456"), true);
  assert.equal(validPin("000000"), true);
  assert.equal(validPin("12345"), false);
  assert.equal(validPin("1234567"), false);
  assert.equal(validPin("１２３４５６"), false);
  assert.equal(validPin(123456), false);
});

test("PIN hash is salted and verifies only the correct PIN", async () => {
  const first = await hashPin("012345");
  const second = await hashPin("012345");
  assert.notEqual(first.pinSalt, second.pinSalt);
  assert.notEqual(first.pinHash, second.pinHash);
  assert.equal(await verifyPin("012345", first), true);
  assert.equal(await verifyPin("999999", first), false);
  assert.equal(await verifyPin("012345", { pinSalt: "bad", pinHash: "bad" }), false);
});

test("invalid PIN values cannot be hashed", async () => {
  await assert.rejects(() => hashPin("12345"), TypeError);
  await assert.rejects(() => hashPin("abcdef"), TypeError);
});

test("fifth consecutive failure locks PIN for fifteen minutes", () => {
  const now = 1_800_000_000_000;
  let state = { pinAttempts: 0, pinLockedUntil: 0 };
  for (let i = 0; i < 4; i++) state = nextPinFailure(state.pinAttempts, now);
  assert.equal(state.pinAttempts, 4);
  assert.equal(state.locked, false);
  state = nextPinFailure(state.pinAttempts, now);
  assert.equal(state.pinAttempts, 0);
  assert.equal(state.pinLockedUntil, now + 15 * 60 * 1000);
  assert.equal(state.locked, true);
});
