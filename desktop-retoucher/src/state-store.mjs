import { mkdir, readFile, rename, writeFile } from 'node:fs/promises';
import { dirname } from 'node:path';

export const emptyState = () => ({
  version: 1,
  jobs: {},
  exports: {},
});

export async function loadState(path) {
  try {
    const parsed = JSON.parse(await readFile(path, 'utf8'));
    return {
      version: 1,
      jobs: parsed?.jobs && typeof parsed.jobs === 'object' ? parsed.jobs : {},
      exports: parsed?.exports && typeof parsed.exports === 'object' ? parsed.exports : {},
    };
  } catch {
    return emptyState();
  }
}

export async function saveState(path, state) {
  await mkdir(dirname(path), { recursive: true });
  const temp = `${path}.${process.pid}.tmp`;
  await writeFile(temp, `${JSON.stringify(state, null, 2)}\n`, 'utf8');
  await rename(temp, path);
}
