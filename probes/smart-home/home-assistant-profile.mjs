// SPDX-License-Identifier: BSD-2-Clause
// AI-assisted dependency inventory from pinned upstream manifests, not a launcher.
import assert from 'node:assert/strict';
import {mkdir, readFile, writeFile} from 'node:fs/promises';
import path from 'node:path';

const [source, work] = process.argv.slice(2);
assert(source && work && path.isAbsolute(source) && path.isAbsolute(work),
    'Usage: node home-assistant-profile.mjs ABSOLUTE_SOURCE NEW_ABSOLUTE_WORK');
const metadata = await readFile(path.join(source, 'pyproject.toml'), 'utf8');
assert.match(metadata, /^version = "2026\.9\.4"$/m, 'Use the pinned Core release');
const generated = await readFile(path.join(source, 'homeassistant/generated/entity_platforms.py'), 'utf8');
const platforms = [...generated.matchAll(/^    [A-Z_]+ = "([a-z_]+)"/gm)].map(match => match[1]);
assert.equal(platforms.length, 45, 'Upstream entity platform inventory changed');
const components = new Set();
const requirements = new Set();
async function visit(name) {
    assert.match(name, /^[a-z][a-z0-9_]*$/);
    if (components.has(name)) return;
    components.add(name);
    const manifest = JSON.parse(await readFile(path.join(source,
        'homeassistant/components', name, 'manifest.json'), 'utf8'));
    assert.equal(manifest.domain, name);
    for (const requirement of manifest.requirements ?? []) {
        assert.equal(typeof requirement, 'string');
        assert(!requirement.includes('\n') && !requirement.startsWith('-'));
        requirements.add(requirement);
    }
    for (const dependency of manifest.dependencies ?? []) await visit(dependency);
}
// Bootstrap loads entity platforms even without explicit YAML entries.
// Camera imports stream, and analytics imports the hassio API client.
// Installing that client does not install or activate the Linux Supervisor.
for (const component of [...platforms, 'frontend', 'http', 'api', 'onboarding',
    'recorder', 'history', 'mqtt', 'automation', 'script', 'scene', 'otbr',
    'stream', 'hassio', 'analytics']) await visit(component);
await mkdir(work);
await writeFile(path.join(work, 'profile.in'), [...requirements].sort().join('\n') + '\n');
await writeFile(path.join(work, 'components.txt'), [...components].sort().join('\n') + '\n');
await writeFile(path.join(work, 'inventory.json'), JSON.stringify({
    release: '2026.9.4', entityPlatforms: platforms.length,
    components: components.size, integrationRequirements: requirements.size,
    coreRequirements: 'requirements.txt', constraints: 'homeassistant/package_constraints.txt',
    validation: 'dependency inventory only; not native installation or runtime',
}, null, 2) + '\n');
console.log(`Inventoried ${platforms.length} entity platforms, ${components.size} components, ${requirements.size} integration requirements`);
