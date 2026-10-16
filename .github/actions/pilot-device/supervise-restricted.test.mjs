import {test} from 'node:test';
import assert from 'node:assert/strict';
import {generateKeyPairSync,privateDecrypt,constants} from 'node:crypto';
import {encryptPairing,identityMatchesRun,pairingReady} from './supervise-restricted.mjs';

test('pairing data encrypted with RSA OAEP, never plaintext',()=>{
 const {publicKey,privateKey}=generateKeyPairSync('rsa',{modulusLength:2048});
 const cipher=encryptPairing('device code: SECRET-EXAMPLE',publicKey);
 assert.match(cipher,/PILOT_ENCRYPTED_PAIRING_BEGIN/);
 assert.doesNotMatch(cipher,/SECRET-EXAMPLE/);
 const data=cipher.match(/PILOT_PAIR_0=([^\r\n]+)/)[1];
 const out=privateDecrypt({key:privateKey,padding:constants.RSA_PKCS1_OAEP_PADDING,oaepHash:'sha256'},Buffer.from(data,'base64')).toString('utf8');
 assert.equal(out,'device code: SECRET-EXAMPLE');
});
test('both pairing readiness markers are required',()=>{
 assert.equal(pairingReady('device code received'),false);
 assert.equal(pairingReady('waiting for authorization'),false);
 assert.equal(pairingReady('device code received\nwaiting for authorization'),true);
});
test('session must belong to exact workflow run',()=>{
 const root='E:/DevBox/Tools/WindowsStateProbe/probe-999-1';
 assert.equal(identityMatchesRun({schema:1,runId:'123',root,deadlineMs:Date.now()+100000},'123'),true);
 assert.equal(identityMatchesRun({schema:1,runId:'999',root,deadlineMs:Date.now()+100000},'123'),false);
 assert.equal(identityMatchesRun({schema:1,runId:'123',root,deadlineMs:Date.now()-1000},'123'),false);
});
