// SPDX-License-Identifier: BSD-2-Clause
// AI-assisted regression for the TEST HARNESS, using an intentional fake server.
// This fixture never constitutes Zigbee2MQTT runtime evidence.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdir, readFile, writeFile} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const [work, harnessOverride] = process.argv.slice(2);
assert(work && path.isAbsolute(work), 'Usage: node test-onboarding-exit.mjs NEW_ABSOLUTE_WORK [HARNESS]');
await mkdir(work);
const source = path.join(work, 'fixture');
await mkdir(source);
await writeFile(path.join(source, 'package.json'), '{"version":"harness-fixture"}\n');
await writeFile(path.join(source, 'index.js'), `
const {createServer}=require('node:http');
const address=new URL(process.env.Z2M_ONBOARD_URL);
createServer((req,res)=>{
  if(req.url==='/data') {res.setHeader('Content-Type','application/json');
    res.end(JSON.stringify({page:'form',settings:{},settingsSchema:{},devices:[]}));}
  else {res.setHeader('Content-Type','text/html');res.end('<html>Fixture</html>');}
}).listen(Number(address.port), address.hostname);
process.on('SIGTERM',()=>{
  if(process.env.FIXTURE_STOP_MODE!=='ignore') process.exit(Number(process.env.FIXTURE_STOP_MODE));
});
`);
const harness = harnessOverride ?? fileURLToPath(new URL('./test-onboarding.mjs', import.meta.url));
for (const mode of ['0', '1', 'ignore']) {
    let output = '';
    const child = spawn(process.execPath, [harness, source, path.join(work, `case-${mode}`)], {
        env: {...process.env, FIXTURE_STOP_MODE: mode}, stdio: ['ignore', 'pipe', 'pipe'],
    });
    child.stdout.on('data', chunk => {output += chunk;});
    child.stderr.on('data', chunk => {output += chunk;});
    const result = await new Promise((resolve, reject) => {
        child.once('error', reject);
        child.once('exit', (code, signal) => resolve({code, signal}));
    });
    await writeFile(path.join(work, `${mode}.log`), output);
    assert.equal(result.signal, null);
    assert.equal(result.code === 0, mode === '0', `Incorrect acceptance of shutdown mode ${mode}`);
    if (mode !== '0') {
        await assert.rejects(readFile(path.join(work, `case-${mode}`, 'result.json')), {code: 'ENOENT'});
        assert(!output.includes('PASS:'), 'Failure printed a success result');
    }
    console.log(`PASS: harness shutdown ${mode} ${mode === '0' ? 'accepted' : 'rejected'}`);
}
