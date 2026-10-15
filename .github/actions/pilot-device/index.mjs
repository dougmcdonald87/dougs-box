import { DefaultArtifactClient } from '@actions/artifact';
import { writeFile, readFile } from 'node:fs/promises';
import { drainOperatorRequests } from './operator-worker.mjs';
import { runOperatorPowerShell } from './operator-execution.mjs';
import { spawn } from 'node:child_process';
import { join } from 'node:path';
import { createPublicKey, publicEncrypt, constants } from 'node:crypto';

const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

function encodeEncrypted(text, rsaKey) {
  const bytes = Buffer.from(text, 'utf8');
  const lines = ['PILOT_ENCRYPTED_PAIRING_BEGIN'];
  for (let offset = 0, n = 0; offset < bytes.length; offset += 120, n++) {
    const cipher = publicEncrypt({ key: rsaKey, padding: constants.RSA_PKCS1_OAEP_PADDING, oaepHash: 'sha256' }, bytes.subarray(offset, offset + 120));
    lines.push(`PILOT_PAIR_${n}=${cipher.toString('base64')}`);
  }
  lines.push('PILOT_ENCRYPTED_PAIRING_END');
  return lines.join('\n') + '\n';
}

async function run() {
  const mod = process.env.PILOT_RSA_MODULUS;
  if (!mod) throw new Error('Public pilot encryption key missing.');
  const rsaKey = createPublicKey({ key: { kty: 'RSA', n: Buffer.from(mod, 'base64').toString('base64url'), e: 'AQAB' }, format: 'jwk' });
  const root = process.env.RUNNER_TEMP || process.cwd();
  const file = join(root, 'windows-home-pilot-pairing.encrypted.txt');
  const cmd = process.env.ComSpec || 'cmd.exe';
  const args = ['/d', '/s', '/c', 'npx --yes @wonderwhy-er/desktop-commander@0.2.52 remote --no-persist-session'];
  const device = spawn(cmd, args, { cwd: root, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
  let output = '';
  let exitCode = null;
  let errorType = null;
  const capture = part => { if (output.length < 100000) output += part.toString('utf8').slice(0, 100000 - output.length); };
  device.stdout?.on('data', capture);
  device.stderr?.on('data', capture);
  device.on('error', error => { errorType = error.name; });
  device.on('exit', code => { exitCode = code ?? 'unknown'; });
  console.log('PILOT: remote agent launched; waiting for full verification code.');
  let ready = false;
  const start = Date.now();
  while (Date.now() - start < 300000) {
    await sleep(5000);
    ready = /device code received/i.test(output) && /waiting for authorization/i.test(output);
    if (ready || exitCode !== null || errorType) break;
  }
  const payload = JSON.stringify({
    runId: process.env.GITHUB_RUN_ID,
    pairingReady: ready,
    processExitedBeforeUpload: exitCode !== null,
    spawnErrorClass: errorType,
    diagnostics: output,
  });
  await writeFile(file, encodeEncrypted(payload, rsaKey), { encoding: 'utf8' });
  const upload = await new DefaultArtifactClient().uploadArtifact(
    `windows-home-pilot-pairing-${process.env.GITHUB_RUN_ID}`,
    [file], root, { retentionDays: 1 }
  );
  console.log(`PILOT_ENCRYPTED_ARTIFACT_ID=${upload.id}`);
  console.log(`PILOT_DEVICE_CODE_READY=${ready}`);
  if (!ready) throw new Error('Desktop Commander device-code flow did not reach the authorization stage.');
  if (exitCode !== null || errorType) throw new Error('Remote agent exited before owner authorization.');
  console.log('PILOT: ready for user approval; keeping agent alive in this same GitHub action.');
  // Reserve startup and cleanup time within the 340-minute pilot job.
  const deadline = Date.now() + 300 * 60000;
  let completedFinish = false;
  try {
    const controlDir = process.env.WINDOWS_HOME_CONTROL_DIR;
    let session = null;
    if (controlDir) {
      session = JSON.parse(await readFile(join(controlDir,'session.json'),'utf8'));
      if (session.schema !== 1 || session.runId !== process.env.GITHUB_RUN_ID ||
          !/^devbox-checkpoint-v1-ci-/.test(session.generation) || !Number.isSafeInteger(session.deadlineMs)) {
        throw new Error('Refused mismatched scoped operator session.');
      }
      console.log('PILOT: local owner Save/Finish queue active; guest GUI still requires owner iPhone verification.');
    }
    while (Date.now() < deadline && exitCode === null && !errorType) {
      if (session) {
        const outcome = await drainOperatorRequests({
          root:controlDir,session,
          executor:request=>runOperatorPowerShell(request,{controlDir,workspace:process.env.GITHUB_WORKSPACE})
        });
        if (outcome.verifiedFinish) {
          completedFinish = true;
          console.log('PILOT: encrypted Finish accepted; owner session ending.');
          break;
        }
      }
      await sleep(10000);
    }
    if (exitCode !== null || errorType) throw new Error('Remote agent stopped during user-authorization hold.');
    if (!completedFinish) console.log('PILOT: isolated terminal hold ended without a verified Finish.');
  } finally {
    // Windows cmd.exe may spawn npx and a grandchild agent. Stop the entire tree.
    if (exitCode === null && !errorType) {
      const killer = spawn('taskkill.exe', ['/PID', String(device.pid), '/T', '/F'], { windowsHide: true, stdio: 'ignore' });
      await new Promise(resolve => { killer.once('exit', resolve); killer.once('error', resolve); });
    }
  }
}

await run();
