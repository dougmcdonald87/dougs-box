import test from 'node:test';
import assert from 'node:assert/strict';
import { evaluateGuestAccess } from './guest-access.mjs';

test('host RDP and pairing cannot substitute for guest screen', () => {
  const result = evaluateGuestAccess({hostRdpReady:true, paired:true, guestScreenVisible:false, guestInputConfirmed:false, guestReconnectConfirmed:false});
  assert.equal(result.ready,false);
  assert.ok(result.missing.includes('guestScreenVisible'));
});
test('guest screen without input and reconnect fails', () => {
  assert.equal(evaluateGuestAccess({guestScreenVisible:true,guestInputConfirmed:false,guestReconnectConfirmed:false}).ready,false);
});
test('guest screen plus input and reconnect passes', () => {
  assert.equal(evaluateGuestAccess({guestScreenVisible:true,guestInputConfirmed:true,guestReconnectConfirmed:true}).ready,true);
});
test('truthy strings do not count as proof', () => {
  assert.equal(evaluateGuestAccess({guestScreenVisible:'true',guestInputConfirmed:'true',guestReconnectConfirmed:'true'}).ready,false);
});
