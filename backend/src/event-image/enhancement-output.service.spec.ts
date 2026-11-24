import axios from 'axios';
import { Readable } from 'stream';
import { readFile } from 'fs/promises';
import sharp from 'sharp';
import { EnhancementOutputService, isFalOutputUrl } from './enhancement-output.service';

describe('AI enhancement output storage', () => {
  const originalUrl = 'https://r2.example.test/source.jpg';
  const falUrl = 'https://v3b.fal.media/files/enhanced.png';
  let bytes: Buffer;
  let storage: { canStreamStoredUrl: jest.Mock; openStoredUrl: jest.Mock; uploadFile: jest.Mock };
  let service: EnhancementOutputService;

  beforeEach(async () => {
    bytes = await sharp({ create: { width: 8, height: 8, channels: 3, background: '#b0a090' } }).png().toBuffer();
    storage = {
      canStreamStoredUrl: jest.fn().mockReturnValue(true),
      openStoredUrl: jest.fn().mockImplementation(async () => Readable.from([Buffer.from('different original')])),
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
});
