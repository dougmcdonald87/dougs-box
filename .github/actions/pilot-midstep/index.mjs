import { DefaultArtifactClient } from '@actions/artifact';
import { writeFile } from 'node:fs/promises';
import { join } from 'node:path';

async function main() {
  const base = process.env.RUNNER_TEMP || process.cwd();
  const file = join(base, 'pilot-dummy.txt');
  await writeFile(file, 'harmless dummy payload\n', { encoding: 'utf8' });
  const result = await new DefaultArtifactClient().uploadArtifact(
    `pilot-midstep-${process.env.GITHUB_RUN_ID}`,
    [file],
    base,
    { retentionDays: 1 }
  );
  console.log(`PILOT_MIDSTEP_ARTIFACT_ID=${result.id}`);
  console.log('PILOT_SAME_ACTION_HOLD=START');
  await new Promise(resolve => setTimeout(resolve, 45000));
  console.log('PILOT_SAME_ACTION_HOLD=COMPLETED');
}
await main();
