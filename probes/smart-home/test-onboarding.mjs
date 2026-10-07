// SPDX-License-Identifier: BSD-2-Clause
// AI-assisted HTTP check against the real application; no radio is simulated.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdir, open, readFile, writeFile} from 'node:fs/promises';
import {createServer} from 'node:net';
import {platform, release, arch} from 'node:os';
import path from 'node:path';
import {setTimeout as delay} from 'node:timers/promises';

const [source, work] = process.argv.slice(2);
assert(source && work && path.isAbsolute(source) && path.isAbsolute(work),
    'Usage: node test-onboarding.mjs ABSOLUTE_BUILT_SOURCE NEW_ABSOLUTE_WORK');
await mkdir(work);
await mkdir(path.join(work, 'data'));
const log = await open(path.join(work, 'application.log'), 'wx');
const socket = createServer();
await new Promise((resolve, reject) => {
    socket.once('error', reject);
    socket.listen(0, '127.0.0.1', resolve);
});
const port = socket.address().port;
await new Promise((resolve, reject) => socket.close(error => error ? reject(error) : resolve()));
const url = `http://127.0.0.1:${port}`;
const env = {...process.env};
for (const name of Object.keys(env)) {
    if (/^(Z2M_|ZIGBEE2MQTT_)/.test(name)) delete env[name];
}
Object.assign(env, {
    ZIGBEE2MQTT_DATA: path.join(work, 'data'), Z2M_ONBOARD_URL: url,
    Z2M_ONBOARD_FORCE_RUN: '1', Z2M_ONBOARD_NO_REDIRECT: '1',
});
const child = spawn(process.execPath, [path.join(source, 'index.js')], {
    cwd: source, env, stdio: ['ignore', log.fd, log.fd],
});
let ended = false;
const exit = new Promise(resolve => {
    child.once('exit', (code, signal) => { ended = true; resolve({code, signal}); });
    child.once('error', error => { ended = true; resolve({error: error.message}); });
});
let validationResult;
try {
    let html;
    for (let attempt = 0; attempt < 60; attempt++) {
        assert(!ended, 'Application exited before onboarding became available');
        try {
            const response = await fetch(url, {signal: AbortSignal.timeout(1000)});
            if (response.ok) {
                assert.match(response.headers.get('content-type'), /text\/html/);
                html = await response.text();
                break;
            }
        } catch (error) {
            if (error instanceof assert.AssertionError) throw error;
        }
        await delay(250);
    }
    assert.match(html ?? '', /<html/i, 'Real onboarding page did not load');
    const response = await fetch(`${url}/data`, {signal: AbortSignal.timeout(15000)});
    assert.equal(response.status, 200);
    const data = await response.json();
    assert.equal(data.page, 'form');
    assert.equal(typeof data.settings, 'object');
    assert.equal(typeof data.settingsSchema, 'object');
    assert(Array.isArray(data.devices));
    assert(data.devices.every(device => typeof device.path === 'string'));
    const pkg = JSON.parse(await readFile(path.join(source, 'package.json'), 'utf8'));
    validationResult = {
        version: pkg.version, node: process.version, platform: platform(), release: release(), arch: arch(),
        checks: ['HTTP onboarding page', 'settings and schema API', 'actual device enumeration API'],
        enumeratedPaths: data.devices.length, radioPairing: 'not tested',
    };
} finally {
    if (!ended) child.kill('SIGTERM');
    let result = await Promise.race([exit, delay(5000).then(() => undefined)]);
    if (!result) {
        child.kill('SIGKILL');
        result = await exit;
    }
    await writeFile(path.join(work, 'exit.json'), JSON.stringify(result) + '\n');
    await log.close();
    assert.equal(result.error, undefined, 'Application spawn failed');
    assert.equal(result.signal, null, 'Application required or suffered a signal termination');
    assert.equal(result.code, 0, 'Application did not shut down cleanly');
}
await writeFile(path.join(work, 'result.json'), JSON.stringify(validationResult, null, 2) + '\n');
console.log(`PASS: real Zigbee2MQTT ${validationResult.version} onboarding HTTP/API and clean shutdown on ${platform()}/${arch()}`);
