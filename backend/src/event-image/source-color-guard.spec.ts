import { mkdtemp, rm, writeFile } from 'fs/promises';
import { tmpdir } from 'os';
import { join } from 'path';
import sharp from 'sharp';
import { hasWarmColorRegression } from './source-color-guard';

describe('Source color regression detection', () => {
  let dir: string;
  let source: string;
  let result: string;

  async function image(color: string) {
    const patch = await sharp({ create: { width: 80, height: 100, channels: 3, background: color } }).png().toBuffer();
    return sharp({ create: { width: 256, height: 256, channels: 3, background: '#31506b' } })
      .composite([{ input: patch, left: 64, top: 40 }]).png().toBuffer();
  }

  beforeEach(async () => {
    dir = await mkdtemp(join(tmpdir(), 'airpix-color-test-'));
    source = join(dir, 'source.png');
    result = join(dir, 'result.png');
  });
  afterEach(async () => { await rm(dir, { recursive: true, force: true }); });

  it.each([
    ['#e8d2ca', '#8e604a', true, 'light source colors turning brown'],
    ['#e8d2ca', '#9b8c87', true, 'severe darkening without a large hue change'],
    ['#e8d2ca', '#e1a573', true, 'an orange cast at similar brightness'],
    ['#e8d2ca', '#ebd6ce', false, 'small color refinements'],
    ['#69503c', '#82604e', false, 'retaining a naturally darker source color'],
    ['#8c766b', '#a58c82', false, 'lifting underexposure without tanning'],
    ['#d2bea0', '#505050', false, 'a neutral vehicle privacy mask'],
    ['#bfcdde', '#e6d2c8', false, 'a correction from an obvious blue source cast'],
  ])('handles %s to %s: %s (%s)', async (before, after, expected) => {
    await writeFile(source, await image(before));
    await writeFile(result, await image(after));
    expect(await hasWarmColorRegression(source, result)).toBe(expected);
  });

  it('ignores compression changes rather than requiring identical skin pixels', async () => {
    const original = await image('#e8d2ca');
    await writeFile(source, await sharp(original).jpeg({ quality: 90 }).toBuffer());
    await writeFile(result, original);
    expect(await hasWarmColorRegression(source, result)).toBe(false);
  });

  it('does not reject a few localized blemish edits as a complexion change', async () => {
    const original = await image('#e8d2ca');
    const blemish = await sharp({ create: { width: 3, height: 3, channels: 3, background: '#98654b' } }).png().toBuffer();
    await writeFile(source, original);
    await writeFile(result, await sharp(original).composite([{ input: blemish, left: 80, top: 80 }]).png().toBuffer());
    expect(await hasWarmColorRegression(source, result)).toBe(false);
  });
});
