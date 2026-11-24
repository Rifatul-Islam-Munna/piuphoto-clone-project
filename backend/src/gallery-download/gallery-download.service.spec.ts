import { BadRequestException, ForbiddenException, NotFoundException } from '@nestjs/common';
import { Readable, Writable } from 'node:stream';
import { createHmac } from 'node:crypto';
import { GalleryDownloadService, safePhotoEntryName } from './gallery-download.service';
import { streamPhotoZip } from './stream-photo-zip';
import { MinioService } from '../lib/minio.service';

const eventId = '507f191e810c19729de860ea';
const first = '507f1f77bcf86cd799439011';
const second = '507f1f77bcf86cd799439012';
const bucket = 'https://photos.example.test/gallery';

function setup(rows: Array<Record<string, unknown>>) {
  const events = { findPublicByEvent: jest.fn().mockResolvedValue({ data: rows }) };
  const guests = { personal: jest.fn().mockResolvedValue({ data: rows }) };
  const storage = {
    canStreamStoredUrl: jest.fn((url: string) => url.startsWith(bucket + '/')),
    openStoredUrl: jest.fn(async () => Readable.from([Buffer.from('photo bytes')])),
  };
  const service = new GalleryDownloadService(
    events as any, guests as any, storage as any,
  );
  return { service, events, guests, storage };
}

describe('native gallery ZIP authorization', () => {
  const publicRows = [
    { _id: first, imageUrl: `${bucket}/2026/image-1.jpg`, purchaseRequired: false },
    { _id: second, imageUrl: `${bucket}/2026/image-2.png`, purchaseRequired: false },
  ];

  it('downloads exactly the currently authorized public gallery rows', async () => {
    const { service, events, storage } = setup(publicRows);
    const entries = await service.prepare({ eventId });
    expect(entries).toHaveLength(2);
    expect(events.findPublicByEvent).toHaveBeenCalledWith(eventId, undefined, undefined);
    expect(entries.map((item) => item.name)).toEqual([
      'airpix-' + first.slice(-12) + '.jpg',
      'airpix-' + second.slice(-12) + '.png',
    ]);
    const input = await entries[0].open(new AbortController().signal);
    const chunks: Buffer[] = [];
    for await (const part of input) chunks.push(Buffer.from(part));
    expect(Buffer.concat(chunks).toString()).toBe('photo bytes');
    expect(storage.openStoredUrl).toHaveBeenCalledWith(publicRows[0].imageUrl, expect.any(AbortSignal));
  });

  it('always archives original bytes even if a compressed preview and view are available', async () => {
    const original = publicRows[0].imageUrl;
    const { service, storage } = setup([{ ...publicRows[0], previewUrl: 'https://cache.example.test/photo.avif', viewUrl: 'https://cache.example.test/view.avif' }]);
    const entries = await service.prepare({ eventId, ids: first });
    await entries[0].open(new AbortController().signal);
    expect(entries[0].name.endsWith('.jpg')).toBe(true);
    expect(storage.openStoredUrl).toHaveBeenCalledWith(original, expect.any(AbortSignal));
  });

  it('enforces paid originals even when an image ID was supplied', async () => {
    const { service } = setup([{ ...publicRows[0], purchaseRequired: true }]);
    await expect(service.prepare({ eventId, ids: first })).rejects.toThrow(ForbiddenException);
    await expect(service.prepare({ eventId })).rejects.toThrow(ForbiddenException);
  });

  it('uses guest token verification and personal matches instead of all public images', async () => {
    const { service, guests, events } = setup([publicRows[0]]);
    const entries = await service.prepare({ eventId, guestToken: 'guest-secret', albumId: second });
    expect(entries).toHaveLength(1);
    expect(guests.personal).toHaveBeenCalledWith({ eventId, albumId: second, guestToken: 'guest-secret' });
    expect(events.findPublicByEvent).not.toHaveBeenCalled();
  });

  it('rejects requests for photos outside the authorized result set', async () => {
    const { service } = setup([publicRows[0]]);
    await expect(service.prepare({ eventId, ids: second })).rejects.toThrow(ForbiddenException);
    await expect(service.prepare({ eventId, ids: 'broken' })).rejects.toThrow(BadRequestException);
  });

  it('rejects external photo URLs rather than fetching SSRF hosts', async () => {
    const { service, storage } = setup([
      { _id: first, imageUrl: 'https://some-other-site.test/admin' },
    ]);
    await expect(service.prepare({ eventId })).rejects.toThrow(BadRequestException);
    expect(storage.openStoredUrl).not.toHaveBeenCalled();
  });

  it('rejects an empty gallery', async () => {
    const { service } = setup([]);
    await expect(service.prepare({ eventId })).rejects.toThrow(NotFoundException);
  });

  it('preserves common extension when creating photo ZIP entries', () => {
    expect(safePhotoEntryName({ _id: first, imageUrl: `${bucket}/x.heic` }, 0)).toBe(`airpix-${first.slice(-12)}.heic`);
    expect(safePhotoEntryName({ _id: second, imageUrl: `${bucket}/x.mov`, mediaType: 'video' }, 0)).toBe(`airpix-${second.slice(-12)}.mov`);
  });
});

describe('streaming ZIP output', () => {
  it('writes a valid ZIP stream with both filenames and bytes', async () => {
    const written: Buffer[] = [];
    const destination = new Writable({
      write(chunk, _encoding, callback) {
        written.push(Buffer.from(chunk));
        callback();
      },
    });
    await streamPhotoZip([
      { name: 'first.jpg', open: async () => Readable.from(['file-one']) },
      { name: 'second.png', open: async () => Readable.from(['file-two']) },
    ], destination, new AbortController().signal);
    const archive = Buffer.concat(written);
    expect(archive.subarray(0, 2).toString()).toBe('PK');
    expect(archive.includes(Buffer.from('first.jpg'))).toBe(true);
    expect(archive.includes(Buffer.from('second.png'))).toBe(true);
    expect(archive.includes(Buffer.from('file-one'))).toBe(true);
    expect(archive.includes(Buffer.from('file-two'))).toBe(true);
  });
});

describe('storage origin guard', () => {
  it('does not allow the browser fallback to pull arbitrary internet hosts', () => {
    const storage = new MinioService({} as any);
    (storage as any).publicUrl = bucket;
    expect(storage.canStreamStoredUrl(`${bucket}/photos/a%20b.jpg`)).toBe(true);
    expect(storage.canStreamStoredUrl('https://evil.example.test/internal')).toBe(false);
    expect(storage.canStreamStoredUrl(`${bucket}.evil.example.test/photos.jpg`)).toBe(false);
    expect(storage.canStreamStoredUrl(`${bucket}/../private.jpg`)).toBe(false);
  });

  it('supports correctly signed R2 private-file URLs when no public domain exists', () => {
    const storage = new MinioService({} as any);
    (storage as any).publicUrl = '';
    (storage as any).bucketName = 'event-storage';
    (storage as any).urlSecret = 'this-is-a-test-storage-secret';
    const key = '2026/photo name.heic';
    const token = createHmac('sha256', 'this-is-a-test-storage-secret')
      .update(JSON.stringify(['event-storage', key]))
      .digest('hex');
    const url = `https://api.example.test/image/file/${encodeURIComponent(key)}?token=${token}`;
    expect(storage.canStreamStoredUrl(url)).toBe(true);
    expect(storage.canStreamStoredUrl(url.replace('token=', 'token=0000'))).toBe(false);
    expect(storage.canStreamStoredUrl('https://evil.example.test/image/file/private.jpg')).toBe(false);
  });
});
