import axios from 'axios';
import { Readable } from 'stream';
import { readFile } from 'fs/promises';
import sharp from 'sharp';
import { EnhancementOutputService, isFalOutputUrl } from './enhancement-output.service';
import { SOURCE_COLOR_REJECTION_MESSAGE } from './source-color-guard';

describe('AI enhancement output storage', () => {
  const originalUrl = 'https://r2.example.test/source.jpg';
  const falUrl = 'https://v3b.fal.media/files/enhanced.png';
  let bytes: Buffer;
  let storage: { canStreamStoredUrl: jest.Mock; openStoredUrl: jest.Mock; uploadFile: jest.Mock };
  let service: EnhancementOutputService;

  beforeEach(async () => {
    bytes = await sharp({ create: { width: 8, height: 8, channels: 3, background: '#b0a090' } }).png().toBuffer();
    const original = await sharp(bytes).jpeg().toBuffer();
    storage = {
      canStreamStoredUrl: jest.fn().mockReturnValue(true),
      openStoredUrl: jest.fn().mockImplementation(async () => Readable.from([original])),
      uploadFile: jest.fn().mockImplementation(async (file) => {
        expect(await readFile(file.path)).toEqual(bytes);
        expect(file.mimetype).toBe('image/png');
        return 'https://r2.example.test/' + file.filename;
      }),
    };
    service = new EnhancementOutputService(storage as any);
    jest.spyOn(axios, 'get').mockImplementation(async () => ({
      data: Readable.from([bytes]), headers: { 'content-length': String(bytes.length) },
    }));
  });
  afterEach(() => jest.restoreAllMocks());

  it('preserves full-size enhanced bytes in the existing storage bucket', async () => {
    const id = '507f1f77bcf86cd799439011';
    const url = await service.save(originalUrl, falUrl, id, 'test-request');
    expect(url).toMatch(/^https:\/\/r2\.example\.test\/enhanced\/507f1f77bcf86cd799439011\/[a-f0-9]{64}\.png$/);
    const file = storage.uploadFile.mock.calls[0][0];
    await expect(readFile(file.path)).rejects.toMatchObject({ code: 'ENOENT' });
    expect(storage.openStoredUrl).toHaveBeenCalledWith(originalUrl, expect.any(AbortSignal));
    expect(axios.get).toHaveBeenCalledWith(falUrl, expect.objectContaining({ maxRedirects: 0, responseType: 'stream' }));
  });

  it('does not publish an identical copy as a successful enhancement', async () => {
    storage.openStoredUrl.mockImplementation(async () => Readable.from([bytes]));
    await expect(service.save(originalUrl, falUrl)).rejects.toThrow('unchanged copy');
    expect(storage.uploadFile).not.toHaveBeenCalled();
  });

  it('rejects input URL reuse and unrelated output hosts before fetching', async () => {
    await expect(service.save(originalUrl, originalUrl)).rejects.toThrow('without editing');
    await expect(service.save(originalUrl, 'https://fal.media.evil.test/photo.png')).rejects.toThrow('Invalid AI output host');
    expect(axios.get).not.toHaveBeenCalled();
    expect(isFalOutputUrl('http://fal.media/a.jpg')).toBe(false);
    expect(isFalOutputUrl('https://storage.googleapis.com/falserverless/example.png')).toBe(true);
  });

  it('corrects a nearly unchanged low-light result before storing it as enhanced', async () => {
    const dark = await sharp({ create: { width: 96, height: 64, channels: 3, background: '#302218' } }).png().toBuffer();
    bytes = await sharp(dark).png({ compressionLevel: 9 }).toBuffer();
    storage.openStoredUrl.mockImplementation(async () => Readable.from([dark]));
    storage.uploadFile.mockImplementation(async file => {
      const output = await readFile(file.path);
      const originalStats = await sharp(bytes).stats();
      const outputStats = await sharp(output).stats();
      expect(output.equals(bytes)).toBe(false);
      expect(outputStats.channels[1].mean).toBeGreaterThan(originalStats.channels[1].mean * 1.3);
      expect(await sharp(output).metadata()).toMatchObject({ width: 96, height: 64, format: 'png' });
      return 'https://r2.example.test/' + file.filename;
    });

    await expect(service.save(originalUrl, falUrl, undefined, undefined,
      { exposure: 95, shadows: 95, color: 60, lowLight: true })).resolves.toMatch(/\.png$/);
    expect(storage.uploadFile).toHaveBeenCalledTimes(1);
  });

  it('can finish an identical dark AI copy instead of accepting it unchanged', async () => {
    bytes = await sharp({ create: { width: 32, height: 32, channels: 3, background: '#302218' } }).png().toBuffer();
    storage.openStoredUrl.mockImplementation(async () => Readable.from([bytes]));
    storage.uploadFile.mockResolvedValue('https://r2.example.test/corrected.png');
    await expect(service.save(originalUrl, falUrl, undefined, undefined,
      { exposure: 95, shadows: 95, color: 0, lowLight: true })).resolves.toContain('corrected.png');
  });

  it('preserves provider bytes when the source was already properly exposed', async () => {
    const source = await sharp(bytes).jpeg().toBuffer();
    storage.openStoredUrl.mockImplementation(async () => Readable.from([source]));
    await expect(service.save(originalUrl, falUrl, undefined, undefined,
      { exposure: 95, shadows: 95, color: 60, lowLight: true })).resolves.toMatch(/\.png$/);
    expect(storage.uploadFile).toHaveBeenCalledTimes(1);
  });

  it('still rejects an unchanged well-lit copy when finishing is enabled', async () => {
    storage.openStoredUrl.mockImplementation(async () => Readable.from([bytes]));
    await expect(service.save(originalUrl, falUrl, undefined, undefined,
      { exposure: 95, shadows: 95, color: 60, lowLight: true })).rejects.toThrow('unchanged copy');
    expect(storage.uploadFile).not.toHaveBeenCalled();
  });

  it.each([undefined, { exposure: 95, shadows: 95, color: 60, lowLight: true }])(
    'rejects a tanned/darkened result before storage or exposure finishing (%s)', async options => {
      const original = await sharp({ create: { width: 64, height: 64, channels: 3, background: '#e8d2ca' } }).png().toBuffer();
      bytes = await sharp({ create: { width: 64, height: 64, channels: 3, background: '#8e604a' } }).png().toBuffer();
      storage.openStoredUrl.mockImplementation(async () => Readable.from([original]));
      await expect(service.save(originalUrl, falUrl, undefined, undefined, options)).rejects.toThrow(SOURCE_COLOR_REJECTION_MESSAGE);
      expect(storage.uploadFile).not.toHaveBeenCalled();
    },
  );
});
