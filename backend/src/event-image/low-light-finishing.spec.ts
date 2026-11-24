import { mkdtemp, readFile, rm, writeFile } from 'fs/promises';
import { join } from 'path';
import { tmpdir } from 'os';
import sharp from 'sharp';
import { finishLowLight } from './low-light-finishing';

describe('Measured low-light finishing', () => {
  let dir: string;
  let source: string;
  let result: string;
  let corrected: string;
  const options = { exposure: 95, shadows: 95, color: 60, lowLight: true };

  async function photo(level: number) {
    const data = Buffer.alloc(96 * 64 * 3);
    for (let y = 0; y < 64; y += 1) {
      for (let x = 0; x < 96; x += 1) {
        const index = (y * 96 + x) * 3;
        const value = level + x % 24;
        const pixel = x < 4 && y < 4 ? [255, 255, 255] : [value + 12, value, value - 8];
        data.set(pixel, index);
      }
    }
    return sharp(data, { raw: { width: 96, height: 64, channels: 3 } }).png().toBuffer();
  }

  beforeEach(async () => {
    dir = await mkdtemp(join(tmpdir(), 'airpix-light-test-'));
    source = join(dir, 'source.png');
    result = join(dir, 'result.png');
    corrected = join(dir, 'corrected.png');
    const dark = await photo(22);
    await Promise.all([writeFile(source, dark), writeFile(result, dark)]);
  });
  afterEach(async () => { await rm(dir, { recursive: true, force: true }); });

  it('visibly lifts a dark, colorful result while retaining resolution and white highlights', async () => {
    expect(await finishLowLight(source, result, corrected, options)).toBe(true);
    const before = await sharp(result).raw().toBuffer();
    const { data, info } = await sharp(corrected).raw().toBuffer({ resolveWithObject: true });
    const mean = (pixels: Buffer) => pixels.reduce((sum, value) => sum + value, 0) / pixels.length;
    expect(mean(data)).toBeGreaterThan(mean(before) * 1.3);
    expect(info).toMatchObject({ width: 96, height: 64, channels: 3 });
    // Gamma/Lab conversion may round white by one 8-bit level.
    for (const channel of data.subarray(0, 3)) expect(channel).toBeGreaterThanOrEqual(254);
    expect(data[0]).toBe(data[1]);
    expect(data[1]).toBe(data[2]);
    const sample = (32 * 96 + 32) * 3;
    expect(data[sample] - data[sample + 2]).toBeGreaterThan(before[sample] - before[sample + 2]);
  });

  it('also catches severe underexposure when the owner leaves the preset on auto', async () => {
    expect(await finishLowLight(source, result, corrected, { ...options, lowLight: false })).toBe(true);
  });

  it('does not double-brighten a result that the AI already corrected', async () => {
    await writeFile(result, await photo(115));
    expect(await finishLowLight(source, result, corrected, options)).toBe(false);
    await expect(readFile(corrected)).rejects.toMatchObject({ code: 'ENOENT' });
  });

  it('does not apply a low-light grade to a properly exposed source', async () => {
    await writeFile(source, await photo(130));
    expect(await finishLowLight(source, result, corrected, options)).toBe(false);
  });

  it.each(['exposure', 'shadows'])('honors an OFF %s control', async control => {
    expect(await finishLowLight(source, result, corrected, { ...options, [control]: 0 })).toBe(false);
    await expect(readFile(corrected)).rejects.toMatchObject({ code: 'ENOENT' });
  });

  it('does not add saturation when the color control is OFF', async () => {
    expect(await finishLowLight(source, result, corrected, { ...options, color: 0 })).toBe(true);
    const plain = await sharp(corrected).raw().toBuffer();
    expect(await finishLowLight(source, result, corrected, options)).toBe(true);
    const colored = await sharp(corrected).raw().toBuffer();
    const index = (32 * 96 + 32) * 3;
    expect(colored[index] - colored[index + 2]).toBeGreaterThan(plain[index] - plain[index + 2]);
  });

  it('does not wash out a near-black scene with only a small bright subject', async () => {
    const night = await sharp({ create: { width: 100, height: 100, channels: 3, background: '#000000' } })
      .composite([{ input: await sharp(await photo(150)).resize(12, 12).toBuffer(), left: 0, top: 0 }]).png().toBuffer();
    await writeFile(source, night);
    await writeFile(result, night);
    expect(await finishLowLight(source, result, corrected, options)).toBe(false);
  });

  it('does not invent color or detail in an unrecoverable black image', async () => {
    const black = await sharp({ create: { width: 96, height: 64, channels: 3, background: '#020202' } }).png().toBuffer();
    await writeFile(source, black);
    expect(await finishLowLight(source, result, corrected, options)).toBe(false);
  });
});
