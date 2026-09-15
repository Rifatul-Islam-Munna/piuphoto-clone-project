import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { loadState, saveState } from '../src/state-store.mjs';

async function tempState() {
  const dir = await mkdtemp(join(tmpdir(), 'airpix-desktop-'));
  return { dir, path: join(dir, 'state.json') };
}

test('desktop sync state survives restart', async () => {
  const { dir, path } = await tempState();
  const expected = { version: 1, jobs: { a: { sha256: 'abc' } }, exports: {} };
  await saveState(path, expected);
  assert.deepEqual(await loadState(path), expected);
  await rm(dir, { recursive: true, force: true });
});

test('corrupt state falls back safely', async () => {
  const { dir, path } = await tempState();
  await writeFile(path, '{broken', 'utf8');
  assert.deepEqual(await loadState(path), { version: 1, jobs: {}, exports: {} });
  await rm(dir, { recursive: true, force: true });
});
test('atomic save writes readable JSON without a temp file dependency', async () => {
  const { dir, path } = await tempState();
  await saveState(path, { version: 1, jobs: {}, exports: { x: { sha256: '123' } } });
  const raw = await readFile(path, 'utf8');
  const parsed = JSON.parse(raw);
  assert.equal(parsed.exports.x.sha256, '123');
  await rm(dir, { recursive: true, force: true });
});
