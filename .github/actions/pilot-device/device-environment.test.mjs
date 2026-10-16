import test from 'node:test';
import assert from 'node:assert/strict';
import { sandboxDeviceEnvironment } from './device-environment.mjs';

test('third-party pairing agent receives only system variables, never runner or backup secrets',()=>{
 const env={PATH:'C:\\Node',SystemRoot:'C:\\Windows',ComSpec:'C:\\Windows\\cmd.exe',TEMP:'C:\\Temp',
  GH_TOKEN:'fake-repo-token',GITHUB_TOKEN:'fake-gh-token',RESTIC_PASSWORD:'fake-backup-secret',
  ACTIONS_ID_TOKEN_REQUEST_TOKEN:'fake-oidc-secret',ACTIONS_ID_TOKEN_REQUEST_URL:'fake-oidc-url',
  DEVBOX_RDP_PASSWORD:'fake-rdp-password',PILOT_RSA_MODULUS:'not-needed-by-agent',
  SOME_PRIVATE_KEY:'must-not-leak'};
 const clean=sandboxDeviceEnvironment(env);
 assert.deepEqual(Object.keys(clean).sort(),['ComSpec','PATH','SystemRoot','TEMP'].sort());
 assert.equal(clean.PATH,'C:\\Node');
 for(const key of ['GH_TOKEN','GITHUB_TOKEN','RESTIC_PASSWORD','ACTIONS_ID_TOKEN_REQUEST_TOKEN','DEVBOX_RDP_PASSWORD','SOME_PRIVATE_KEY']){
  assert.equal(clean[key],undefined,key+' leaked');
 }
});
test('case-insensitive Windows keys are allowed but lookalike attacker keys refused',()=>{
 const clean=sandboxDeviceEnvironment({path:'a',windir:'b',HOME:'c','PATH_SECRET':'bad',npm_config_auth:'bad'});
 assert.equal(clean.path,'a');assert.equal(clean.windir,'b');assert.equal(clean.HOME,'c');
 assert.equal(clean.PATH_SECRET,undefined);assert.equal(clean.npm_config_auth,undefined);
});
