// SPDX-License-Identifier: BSD-2-Clause
// AI-assisted contract for the patched npm module, independent of USB hardware.
'use strict';
const assert = require('node:assert/strict');
const {test} = require('node:test');
const path = require('node:path');
const fs = require('node:fs');
const vm = require('node:vm');
const modulePath = process.env.SERIALPORT_BINDINGS;
if (!modulePath) throw new Error('Set SERIALPORT_BINDINGS to the patched package directory');
const {netbsdList} = require(path.join(modulePath, 'dist/netbsd-list.js'));
const nodeInfo = character => ({isCharacterDevice: () => character});

test('NetBSD selects its list while preserving Unix open and other platforms', () => {
    const unix = {open() {}, list() {throw new Error('udevadm must not run on NetBSD');}};
    const darwin = {};
    const windows = {};
    for (const platform of ['netbsd', 'linux', 'darwin', 'win32']) {
        const exports = {};
        const modules = {
            debug: () => () => {}, './linux': {LinuxBinding: unix},
            './darwin': {DarwinBinding: darwin}, './win32': {WindowsBinding: windows},
            './netbsd-list': {netbsdList},
        };
        vm.runInNewContext(fs.readFileSync(path.join(modulePath, 'dist/index.js'), 'utf8'), {
            exports, process: {platform}, require: name => modules[name] ?? {},
        });
        const binding = exports.autoDetect();
        if (platform === 'netbsd') {
            assert.equal(binding.list, netbsdList);
            assert.equal(binding.open, unix.open);
        } else {
            assert.equal(binding, {linux: unix, darwin, win32: windows}[platform]);
        }
    }
});

test('dial-out character nodes only; sorted, no guessed USB identity', async () => {
    const calls = [];
    const io = {
        readdir: async () => ['ttyU0', 'dtyU1', 'dty00', 'dtyU0', 'dtyU2', 'dtyUabc', 'null'],
        lstat: async file => { calls.push(file); return nodeInfo(file !== '/dev/dtyU2'); },
    };
    const ports = await netbsdList('/dev', io);
    assert.deepEqual(ports.map(port => port.path), ['/dev/dty00', '/dev/dtyU0', '/dev/dtyU1']);
    assert.deepEqual(calls, ['/dev/dty00', '/dev/dtyU0', '/dev/dtyU1', '/dev/dtyU2']);
    for (const port of ports) {
        assert.equal(port.vendorId, undefined);
        assert.equal(port.productId, undefined);
        assert.equal(port.serialNumber, undefined);
        assert.equal(port.manufacturer, undefined);
    }
});
test('a node removed during enumeration is skipped', async () => {
    const io = {readdir: async () => ['dtyU0'], lstat: async () => {
        throw Object.assign(new Error('removed'), {code: 'ENOENT'});
    }};
    assert.deepEqual(await netbsdList('/dev', io), []);
});
test('filesystem failures remain visible', async () => {
    const failure = Object.assign(new Error('permission denied'), {code: 'EACCES'});
    await assert.rejects(netbsdList('/dev', {readdir: async () => {throw failure;}}), failure);
    await assert.rejects(netbsdList('/dev', {
        readdir: async () => ['dtyU0'], lstat: async () => {throw failure;},
    }), failure);
});
test('empty enumeration is real, not an assumed USB success', async () => {
    assert.deepEqual(await netbsdList('/dev', {readdir: async () => []}), []);
});
