import test from 'node:test';
import assert from 'node:assert/strict';
import { evaluateGuestAccess } from './guest-access.mjs';

test('self-declared booleans are not sufficient to establish guest access', () => {
 const result = evaluateGuestAccess({guestScreenVisible:true,guestInputConfirmed:true,guestReconnectConfirmed:true});
 assert.equal(result.ready,false);
});

test('verified independent attestation allows guest access', () => {
 const result = evaluateGuestAccess({guestScreenVisible:true,guestInputConfirmed:true,guestReconnectConfirmed:true,attestation:{source:'independent-owner',validated:true}});
 assert.equal(result.ready,true);
});
