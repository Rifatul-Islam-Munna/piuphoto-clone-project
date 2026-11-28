import { execFile } from 'node:child_process';
import sharp from 'sharp';

export const MAX_RECOVERY_BYTES = 64 * 1024 * 1024;
const MAX_PIXELS = 150_000_000;
const MAX_SIDE = 3200;

// FFmpeg uses a different JPEG decoder from libvips. Decode only on the
// failed AirPix path, then produce a bounded, strictly readable JPEG copy.
export async function normalizeJpeg(input: Buffer): Promise<Buffer> {
  if (!input.length || input.length > MAX_RECOVERY_BYTES) {
    throw new Error('JPEG recovery input exceeds the 64 MiB limit');
  }
  const metadata = await sharp(input, { failOn: 'none', limitInputPixels: MAX_PIXELS }).metadata();
  if (metadata.format !== 'jpeg' || !metadata.width || !metadata.height ||
      metadata.width * metadata.height > MAX_PIXELS || metadata.width > 16000 || metadata.height > 16000) {
    throw new Error('JPEG recovery requires a supported JPEG with safe dimensions');
  }
  const decoded = await new Promise<Buffer>((resolve, reject) => {
    const child = execFile(process.env.FFMPEG_PATH || 'ffmpeg', [
      '-hide_banner', '-loglevel', 'error', '-threads', '1', '-err_detect', 'ignore_err',
      '-f', 'mjpeg', '-noautorotate', '-i', 'pipe:0', '-frames:v', '1',
      '-filter_threads', '1', '-vf',
      "scale=w='min(" + MAX_SIDE + ",iw)':h='min(" + MAX_SIDE + ",ih)':force_original_aspect_ratio=decrease",
      '-threads', '1', '-pix_fmt', 'rgb24', '-c:v', 'png', '-f', 'image2pipe', 'pipe:1',
    ], { encoding: 'buffer', timeout: 25_000, maxBuffer: MAX_RECOVERY_BYTES, windowsHide: true },
    (error, stdout) => {
      if (error || !stdout.length) return reject(new Error('FFmpeg could not recover JPEG pixels' +
        (error?.code === 'ENOENT' ? ': ffmpeg is not installed' : error?.killed ? ': decoder timed out' : '')));
      resolve(stdout);
    });
    child.stdin?.on('error', () => { /* child callback reports the decoder failure */ });
    child.stdin?.end(input);
  });

  // FFmpeg's PNG intermediate is lossless; apply EXIF orientation once before
  // stripping metadata. Original image bytes and download URL stay untouched.
  let pipeline = sharp(decoded, { failOn: 'warning', limitInputPixels: MAX_PIXELS });
  switch (metadata.orientation) {
    case 2: pipeline = pipeline.flop(); break;
    case 3: pipeline = pipeline.rotate(180); break;
    case 4: pipeline = pipeline.flip(); break;
    case 5: pipeline = pipeline.flip().rotate(90); break;
    case 6: pipeline = pipeline.rotate(90); break;
    case 7: pipeline = pipeline.flop().rotate(90); break;
    case 8: pipeline = pipeline.rotate(270); break;
  }
  const output = await pipeline.timeout({ seconds: 12 }).jpeg({ quality: 95, chromaSubsampling: '4:4:4' }).toBuffer();
  // Validate the complete derivative with strict libvips before storing it.
  await sharp(output, { failOn: 'warning', limitInputPixels: MAX_PIXELS }).timeout({ seconds: 12 }).stats();
  return output;
}
