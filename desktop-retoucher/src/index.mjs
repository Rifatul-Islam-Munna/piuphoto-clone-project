import { createReadStream, createWriteStream, existsSync, openAsBlob } from 'node:fs';
import { mkdir, readFile, readdir, rename, stat, unlink } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { basename, extname, resolve } from 'node:path';
import { Readable, Transform } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import { loadState, saveState } from './state-store.mjs';

const configPath = resolve(process.env.AIRPIX_DESKTOP_CONFIG || 'airpix-desktop.json');
const config = JSON.parse(await readFile(configPath, 'utf8'));
for (const key of ['backendUrl', 'token', 'eventId']) {
  if (!config[key] || String(config[key]).startsWith('PASTE_')) {
    throw new Error(`${key} must be configured in ${configPath}`);
  }
}

const baseUrl = String(config.backendUrl).replace(/\/$/, '');
const downloadDir = resolve(config.downloadDir || './downloads');
const exportDir = resolve(config.exportDir || './exports');
const stateFile = resolve(config.stateFile || './.airpix-sync-state.json');
const deviceId = config.deviceId || `retoucher-${process.env.COMPUTERNAME || 'desktop'}`;
await Promise.all([mkdir(downloadDir, { recursive: true }), mkdir(exportDir, { recursive: true })]);
let state = await loadState(stateFile);
let stopping = false;
let busy = false;
const sleep = (ms) => new Promise((done) => setTimeout(done, ms));

async function api(path, options = {}) {
  const headers = new Headers(options.headers || {});
  headers.set('access_token', config.token);
  if (options.body && !(options.body instanceof FormData) && !headers.has('Content-Type')) {
    headers.set('Content-Type', 'application/json');
  }
  const response = await fetch(`${baseUrl}${path}`, { ...options, headers });
  const text = await response.text();
  let payload;
  try { payload = text ? JSON.parse(text) : {}; } catch { payload = { message: text }; }
  if (!response.ok) {
    throw new Error(payload?.message || `HTTP ${response.status} ${path}`);
  }
  return payload;
}

async function checksum(path) {
  const hash = createHash('sha256');
  for await (const chunk of createReadStream(path)) hash.update(chunk);
  return hash.digest('hex');
}

function safeRemoteName(url, jobId) {
  try {
    const name = basename(new URL(url).pathname);
    return name && name.includes('.') ? name.replace(/[^a-zA-Z0-9._-]/g, '_') : `${jobId}.jpg`;
  } catch { return `${jobId}.jpg`; }
}
function bandwidthLimiter() {
  const mbps = Math.max(Number(config.maxMbps) || 0, 0);
  if (!mbps) return new Transform({ transform(chunk, _enc, cb) { cb(null, chunk); } });
  const bytesPerSecond = (mbps * 1024 * 1024) / 8;
  return new Transform({
    transform(chunk, _enc, cb) {
      const delay = Math.ceil((chunk.length / bytesPerSecond) * 1000);
      setTimeout(() => cb(null, chunk), delay);
    },
  });
}

async function mapLimit(rows, limit, worker) {
  let cursor = 0;
  const runners = Array.from({ length: Math.min(limit, rows.length) }, async () => {
    while (!stopping) {
      const index = cursor++;
      if (index >= rows.length) return;
      try { await worker(rows[index]); }
      catch (error) { console.error(`[job] ${error.message}`); }
    }
  });
  await Promise.all(runners);
}

async function markStatus(jobId, status, note) {
  return api('/retouch/status', {
    method: 'PATCH',
    body: JSON.stringify({ jobId, status, deviceId, ...(note ? { note } : {}) }),
  });
}
async function downloadJob(job) {
  const jobId = String(job._id);
  if (!job.originalImageUrl) throw new Error(`${jobId}: original URL missing`);
  const target = resolve(downloadDir, `${jobId}__${safeRemoteName(job.originalImageUrl, jobId)}`);
  const partial = `${target}.part`;
  let offset = 0;
  try { offset = (await stat(partial)).size; } catch {}

  const headers = offset > 0 ? { Range: `bytes=${offset}-` } : {};
  const response = await fetch(job.originalImageUrl, { headers });
  if (!response.ok && response.status !== 206) {
    throw new Error(`${jobId}: download HTTP ${response.status}`);
  }
  if (!response.body) throw new Error(`${jobId}: empty download body`);
  const resume = offset > 0 && response.status === 206;
  if (offset > 0 && !resume) await unlink(partial).catch(() => undefined);
  await pipeline(
    Readable.fromWeb(response.body),
    bandwidthLimiter(),
    createWriteStream(partial, { flags: resume ? 'a' : 'w' }),
  );
  await rename(partial, target);
  const sha256 = await checksum(target);
  state.jobs[jobId] = { path: target, sha256, downloadedAt: new Date().toISOString() };
  await saveState(stateFile, state);
  await markStatus(jobId, 'downloaded');
  console.log(`[downloaded] ${jobId} -> ${target}`);
}
async function uploadExport(path, name) {
  const match = name.match(/^([0-9a-fA-F]{24})__(edited|retouched|export)\./);
  if (!match) return;
  const jobId = match[1];
  const sha256 = await checksum(path);
  if (state.exports[path]?.sha256 === sha256) return;

  await markStatus(jobId, 'retouching', 'Desktop export detected');
  const body = new FormData();
  body.append('file', await openAsBlob(path), name);
  const uploaded = await api('/image/upload', { method: 'POST', body });
  if (!uploaded?.url) throw new Error(`${jobId}: uploaded file URL missing`);
  await api('/retouch/version', {
    method: 'POST',
    body: JSON.stringify({
      jobId,
      imageUrl: uploaded.url,
      checksum: sha256,
      deviceId,
      note: 'Uploaded automatically by Airpix Retoucher Desktop',
    }),
  });
  state.exports[path] = { sha256, jobId, uploadedAt: new Date().toISOString() };
  await saveState(stateFile, state);
  console.log(`[uploaded] ${name}`);
}

async function scanExports() {
  for (const entry of await readdir(exportDir, { withFileTypes: true })) {
    if (!entry.isFile()) continue;
    const path = resolve(exportDir, entry.name);
    try { await uploadExport(path, entry.name); }
    catch (error) { console.error(`[export] ${entry.name}: ${error.message}`); }
  }
}
async function fetchFeed() {
  const query = new URLSearchParams({
    eventId: String(config.eventId),
    limit: '500',
  });
  if (config.albumId) query.set('albumId', String(config.albumId));
  return api(`/retouch/desktop-feed?${query.toString()}`);
}

async function cycle() {
  if (busy || stopping) return;
  busy = true;
  try {
    const feed = await fetchFeed();
    const jobs = Array.isArray(feed?.data) ? feed.data : [];
    for (const job of jobs) {
      const saved = state.jobs[String(job._id)];
      if (job.status === 'assigned' && saved?.path && existsSync(saved.path)) {
        await markStatus(String(job._id), 'downloaded').catch((error) =>
          console.error('[reconcile] ' + String(job._id) + ': ' + error.message),
        );
      }
    }
    const pending = jobs.filter((job) => {
      const saved = state.jobs[String(job._id)];
      return !saved?.path || !existsSync(saved.path);
    });
    const configured = Math.max(Number(config.downloadConcurrency) || 3, 1);
    const server = Math.max(Number(feed?.downloadConcurrency) || configured, 1);
    await mapLimit(pending, Math.min(configured, server), downloadJob);
    await scanExports();
  } catch (error) {
    console.error(`[sync] ${error.message}`);
  } finally {
    busy = false;
  }
}

async function heartbeat() {
  try {
    await api('/retouch/desktop-heartbeat', {
      method: 'POST',
      body: JSON.stringify({ eventId: config.eventId, deviceId }),
    });
  } catch (error) { console.error(`[heartbeat] ${error.message}`); }
}
const pollMs = Math.max(Number(config.pollSeconds) || 5, 2) * 1000;
const heartbeatMs = Math.max(Number(config.heartbeatSeconds) || 20, 10) * 1000;
const pollTimer = setInterval(() => void cycle(), pollMs);
const heartbeatTimer = setInterval(() => void heartbeat(), heartbeatMs);
pollTimer.unref?.();
heartbeatTimer.unref?.();

async function stop(signal) {
  if (stopping) return;
  stopping = true;
  clearInterval(pollTimer);
  clearInterval(heartbeatTimer);
  while (busy) await sleep(100);
  await saveState(stateFile, state).catch(() => undefined);
  console.log(`[stopped] ${signal}`);
}

process.on('SIGINT', () => void stop('SIGINT').then(() => process.exit(0)));
process.on('SIGTERM', () => void stop('SIGTERM').then(() => process.exit(0)));

console.log(`Airpix Retoucher Desktop: ${deviceId}`);
console.log(`Event: ${config.eventId}`);
console.log(`Downloads: ${downloadDir}`);
console.log(`Exports: ${exportDir}`);
await heartbeat();
await cycle();
while (!stopping) await sleep(60_000);
