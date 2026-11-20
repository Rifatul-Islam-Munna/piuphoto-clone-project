import { once } from 'node:events';
import { Readable, type Writable } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import archiver from 'archiver';

export type PhotoZipEntry = {
  name: string;
  open: (signal: AbortSignal) => Promise<Readable>;
};

/** Streams one storage object at a time, preserving backpressure to R2. */
export async function streamPhotoZip(
  entries: Iterable<PhotoZipEntry>,
  destination: Writable,
  signal: AbortSignal,
  idleTimeoutMs = 90_000,
) {
  signal.throwIfAborted();
  const archive = archiver('zip', {
    store: true,
    forceZip64: true,
    statConcurrency: 1,
  });
  const controller = new AbortController();
  let source: Readable | undefined;
  let currentEntry: AbortController | undefined;
  let idleTimer: NodeJS.Timeout | undefined;

  const cancel = () => {
    controller.abort(signal.reason ?? new Error('Download cancelled'));
    currentEntry?.abort(controller.signal.reason);
    source?.destroy();
  };
  signal.addEventListener('abort', cancel, { once: true });
  if (signal.aborted) cancel();

  const output = pipeline(archive, destination, { signal: controller.signal });
  void output.catch((error) => {
    controller.abort(error);
    currentEntry?.abort(error);
    source?.destroy();
  });

  try {
    for (const entry of entries) {
      controller.signal.throwIfAborted();
      currentEntry = new AbortController();
      const entrySignal = AbortSignal.any([controller.signal, currentEntry.signal]);
      const armTimeout = () => {
        if (idleTimer) clearTimeout(idleTimer);
        idleTimer = setTimeout(() => {
          const error = new Error('Photo stream stalled');
          currentEntry?.abort(error);
          source?.destroy(error);
        }, idleTimeoutMs);
        idleTimer.unref();
      };
      armTimeout();
      source = await entry.open(entrySignal);
      const input = source;
      input.once('error', (error) => archive.destroy(error));
      entrySignal.throwIfAborted();
      const guarded = Readable.from(
        (async function* () {
          for await (const chunk of input) {
            entrySignal.throwIfAborted();
            armTimeout();
            yield chunk;
          }
          entrySignal.throwIfAborted();
        })(),
        { objectMode: false, highWaterMark: 64 * 1024 },
      );
      guarded.once('error', (error) => archive.destroy(error));
      const appended = once(archive, 'entry', { signal: controller.signal });
      archive.append(guarded, { name: entry.name });
      await appended;
      if (idleTimer) clearTimeout(idleTimer);
      source.destroy();
      source = undefined;
      currentEntry = undefined;
    }
    await archive.finalize();
    await output;
  } catch (error) {
    controller.abort(error);
    currentEntry?.abort(error);
    source?.destroy();
    archive.abort();
    archive.destroy();
    await output.catch(() => undefined);
    throw error;
  } finally {
    if (idleTimer) clearTimeout(idleTimer);
    signal.removeEventListener('abort', cancel);
  }
}
