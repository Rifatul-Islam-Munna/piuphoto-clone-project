import { Injectable, HttpException } from '@nestjs/common';
import axios from 'axios';
import { createHash, randomUUID } from 'crypto';
import { createWriteStream } from 'fs';
import { mkdtemp, rm } from 'fs/promises';
import { tmpdir } from 'os';
import { join } from 'path';
import { Transform } from 'stream';
import { pipeline } from 'stream/promises';
import sharp from 'sharp';
import { MinioService } from '../lib/minio.service';

const MAX_RESULT_BYTES = 64 * 1024 * 1024;

export function isFalOutputUrl(value: string): boolean {
  try {
    const url = new URL(value);
    return url.protocol === 'https:' && !url.username && !url.password &&
      (url.hostname === 'fal.media' || url.hostname.endsWith('.fal.media') ||
        (url.hostname === 'storage.googleapis.com' && url.pathname.startsWith('/falserverless/')));
  } catch { return false; }
}

@Injectable()
export class EnhancementOutputService {
  constructor(private readonly storage: MinioService) {}

  // Keep the full-resolution provider result, without a JPEG re-encode.
  // Download to a bounded temporary file instead of allocating a large RAM buffer.
  async save(sourceUrl: string, outputUrl: string, sourceId?: string, requestId?: string): Promise<string> {
    if (sourceUrl === outputUrl) {
      throw new HttpException('AI returned the original image without editing it', 502);
    }
    if (!isFalOutputUrl(outputUrl)) throw new HttpException('Invalid AI output host', 502);
    const dir = await mkdtemp(join(tmpdir(), 'airpix-enhancement-'));
    const file = join(dir, 'output');
    const signal = AbortSignal.timeout(90_000);
    try {
      const response = await axios.get(outputUrl, {
        responseType: 'stream', timeout: 60_000, maxRedirects: 0, signal,
        headers: { Accept: 'image/*' },
      });
      if (Number(response.headers['content-length']) > MAX_RESULT_BYTES) {
        response.data.destroy();
        throw new HttpException('AI output exceeds the supported file size', 502);
      }
      let bytes = 0;
      const outputHash = createHash('sha256');
      await pipeline(response.data, new Transform({
        transform(chunk: Buffer, _encoding, callback) {
          bytes += chunk.length;
          if (bytes > MAX_RESULT_BYTES) return callback(new Error('AI output exceeds the supported file size'));
          outputHash.update(chunk);
          callback(null, chunk);
        },
      }), createWriteStream(file), { signal });
      if (!bytes) throw new HttpException('AI returned an empty image', 502);
      const meta = await sharp(file, { limitInputPixels: 150_000_000 }).metadata();
      const formats: Record<string, [string, string]> = {
        jpeg: ['jpg', 'image/jpeg'], png: ['png', 'image/png'],
        webp: ['webp', 'image/webp'], avif: ['avif', 'image/avif'],
        ...(meta.compression === 'av1' ? { heif: ['avif', 'image/avif'] as [string, string] } : {}),
      };
      const format = meta.format && formats[meta.format];
      if (!format || !meta.width || !meta.height) {
        throw new HttpException('AI did not return a supported photograph', 502);
      }

      // Reject byte-for-byte duplicates without loading original photos into RAM.
      // Stop reading as soon as the source is larger than the result.
      if (this.storage.canStreamStoredUrl(sourceUrl)) {
        const source = await this.storage.openStoredUrl(sourceUrl, signal);
        const originalHash = createHash('sha256');
        let originalBytes = 0;
        try {
          for await (const chunk of source) {
            const buffer = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
            originalBytes += buffer.length;
            if (originalBytes > bytes) break;
            originalHash.update(buffer);
          }
        } finally { source.destroy(); }
        if (originalBytes === bytes && originalHash.digest('hex') === outputHash.digest('hex')) {
          throw new HttpException('AI returned an unchanged copy of the original photo', 502);
        }
      }

      // Stable per webhook request; retrying a callback cannot create a new key.
      const safeSource = /^[a-f0-9]{24}$/i.test(sourceId || '') ? sourceId : 'photo';
      const identity = requestId ? createHash('sha256').update(requestId).digest('hex') : randomUUID();
      const [extension, mime] = format;
      const filename = 'enhanced/' + safeSource + '/' + identity + '.' + extension;
      const origin = this.storage.canStreamStoredUrl(sourceUrl) &&
        new URL(sourceUrl).pathname.startsWith('/image/file/') ? new URL(sourceUrl).origin : undefined;
      return await this.storage.uploadFile({ path: file, filename, originalname: filename, mimetype: mime }, origin);
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  }
}
