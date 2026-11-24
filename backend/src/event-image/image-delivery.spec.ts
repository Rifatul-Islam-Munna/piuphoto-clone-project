import { createHmac } from 'crypto';
import { Types } from 'mongoose';
import { deliveryConfigVersion, deliveryRows, digestKey, imagorUrls, sourceKey, withDelivery } from './image-delivery';
import { ImagorCacheController, ImagorCacheService } from './imagor-cache.service';

const env = process.env;
const eventId = new Types.ObjectId();
const albumId = new Types.ObjectId();
const row = { _id: new Types.ObjectId(), eventId, albumId, imageUrl: 'https://originals.example.test/a/photo.jpg', mediaType: 'photo' };

beforeEach(() => {
  process.env = { ...env, IMAGOR_ENABLED: 'true', IMAGOR_URL: 'https://imagor.example.test', IMAGOR_SECRET: 'test-only', IMAGOR_SIGNER_TYPE: 'sha256', IMAGOR_SIGNER_TRUNCATE: '40', STORAGE_PUBLIC_URL: 'https://originals.example.test', IMAGOR_RESULT_PUBLIC_URL: 'https://result.example.test' };
});
afterEach(() => { process.env = env; });
const readyRow = () => {
  const urls = imagorUrls(row)!;
  return { ...row, imagorStatus: 'ready', imagorSource: row.imageUrl, imagorConfig: deliveryConfigVersion(), imagorSignature: urls.small + '|' + urls.view,
    imagorSmallUrl: 'https://result.example.test/' + digestKey(urls.small),
    imagorViewUrl: 'https://result.example.test/' + digestKey(urls.view) };
};

describe('Imagor delivery', () => {
  it('signs the routed storage key and never changes the original URL', () => {
    const urls = imagorUrls(row)!;
    const path = urls.small.split('/').slice(4).join('/');
    const signature = createHmac('sha256', 'test-only').update(path).digest('base64').replace(/\+/g, '-').replace(/\//g, '_').slice(0, 40);
    expect(urls.small).toBe('https://imagor.example.test/' + signature + '/' + path);
    expect(path).toContain('format(avif)');
    expect(path).toContain('/piuphoto/a/photo.jpg');
    const result: any = withDelivery(row);
    expect(result.imageUrl).toBe(row.imageUrl);
    expect(result.previewUrl).toBe(urls.small);
    expect(result.deliverySource).toBe('imagor');
    expect(result.viewUrl).toBe(urls.view);
  });
  it('does not sign videos, paid previews, or arbitrary hosts', () => {
    expect(imagorUrls({ ...row, mediaType: 'video' })).toBeUndefined();
    expect(imagorUrls({ ...row, purchaseRequired: true })).toBeUndefined();
    expect(sourceKey('https://originals.example.test.evil.test/a.jpg')).toBeUndefined();
    expect(sourceKey('https://originals.example.test/a%2F..%2Fprivate.jpg')).toBeUndefined();
    expect(sourceKey('https://originals.example.test/a.jpg?x=1')).toBeUndefined();
  });
  it('migrates old signed storage URLs without trusting an arbitrary object key', () => {
    process.env.STORAGE_S3_URL = 'https://account.r2.cloudflarestorage.com';
    process.env.BUCKET = 'airpix';
    process.env.STORAGE_URL_SECRET = 'old-test-signing-key';
    const key = 'folder/old.jpg';
    const token = createHmac('sha256', process.env.STORAGE_URL_SECRET).update(JSON.stringify(['airpix', key])).digest('hex');
    const url = 'https://old-api.example.test/image/file/' + encodeURIComponent(key) + '?token=' + token;
    expect(sourceKey(url)).toBe(key);
    expect(imagorUrls({ ...row, imageUrl: url })!.small).toContain('/piuphoto/folder/old.jpg');
    expect(sourceKey(url.replace('old.jpg', 'other.jpg'))).toBeUndefined();
  });
  it('uses deterministic digest keys compatible with the shared worker', () => {
    expect(digestKey('https://img.example.com/abcdefghijklmnopq/200x200/abc')).toBe('30/fd/be2aa5086e0f0c50ea72dd3859a10d8071ad');
  });
  it('switches a scoped album only after all cache jobs are ready', async () => {
    const photo = readyRow();
    const distinct = jest.fn().mockResolvedValueOnce([eventId]).mockResolvedValueOnce([]);
    const pending: any = (await deliveryRows({ distinct } as any, [photo], String(albumId)))[0];
    expect(pending.previewUrl).toBe(imagorUrls(row)!.small);
    const ready: any = (await deliveryRows({ distinct } as any, [photo], String(albumId)))[0];
    expect(ready.previewUrl).toBe(photo.imagorSmallUrl + '?format=avif');
    expect(pending.deliverySource).toBe('imagor');
    expect(ready.deliverySource).toBe('r2');
    expect(ready.viewUrl).toBe(photo.imagorViewUrl + '?format=avif');
    expect(ready.imageUrl).toBe(row.imageUrl);
    expect(ready.imagorSignature).toBeUndefined();
    expect(distinct.mock.calls[0][1].albumId).toEqual(albumId);
  });
  it('returns verified direct R2 previews per transfer without replacing the original', () => {
    const pending: any = withDelivery(row, true);
    const ready: any = withDelivery(readyRow(), true);
    expect(pending.deliverySource).toBe('imagor');
    expect(ready.deliverySource).toBe('r2');
    expect(ready.previewUrl).toContain('https://result.example.test/');
    expect(ready.imageUrl).toBe(row.imageUrl);
  });
  it('invalidates a ready row when transform settings change', () => {
    const photo = readyRow();
    process.env.IMAGOR_SMALL_WIDTH = '800';
    const result: any = withDelivery(photo, true);
    expect(result.previewUrl).toBe(imagorUrls(row)!.small);
    expect(result.previewUrl).not.toContain('result.example');
  });
  it('remains compatible with legacy delivery when disabled', () => {
    process.env.IMAGOR_ENABLED = 'false';
    expect(withDelivery(row)).toEqual(row);
  });
});

describe('Imagor worker protocol', () => {
  it('authenticates worker requests using only IMAGOR_SECRET', async () => {
    const claim = jest.fn().mockResolvedValue(null);
    const controller = new ImagorCacheController({ claim } as any);
    await expect(controller.claim('incorrect')).rejects.toThrow('Invalid Imagor worker secret');
    expect(claim).not.toHaveBeenCalled();
    await expect(controller.claim('test-only')).resolves.toEqual({ data: null });
  });
  it('claims work with a lease and returns only signed transform URLs', async () => {
    const findOneAndUpdate = jest.fn().mockReturnValue({ lean: async () => row });
    const updateOne = jest.fn().mockResolvedValue({ matchedCount: 1 });
    const service = new ImagorCacheService({ findOneAndUpdate, updateOne } as any);
    const job = await service.claim();
    expect(job!.imageId).toMatch(/^[a-f0-9]{24}~[a-f0-9-]{36}$/);
    expect(job!.urls).toEqual({ small: imagorUrls(row)!.small, view: imagorUrls(row)!.view });
    expect(updateOne.mock.calls[0][0].imageUrl).toBe(row.imageUrl);
  });
  it('only marks a matching lease and verified result keys ready', async () => {
    const urls = imagorUrls(row)!;
    const token = '12345678-1234-1234-1234-123456789abc';
    const photo = { ...row, imagorLease: token, imagorSource: row.imageUrl, imagorConfig: deliveryConfigVersion(), imagorSignature: urls.small + '|' + urls.view };
    const updateOne = jest.fn().mockResolvedValue({ modifiedCount: 1 });
    const service = new ImagorCacheService({ findOne: jest.fn().mockReturnValue({ lean: async () => photo }), updateOne } as any);
    const keys = { small: digestKey(urls.small), view: digestKey(urls.view) };
    const result = { small: 'https://result.example.test/' + keys.small, view: 'https://result.example.test/' + keys.view };
    await expect(service.complete(String(row._id) + '~' + token, { success: true, keys, urls: result })).resolves.toMatchObject({ accepted: true, ready: true });
    expect(updateOne.mock.calls[0][1].$set.imagorStatus).toBe('ready');
    await expect(service.complete(String(row._id) + '~' + token, { success: true, keys, urls: { ...result, small: 'https://evil.test/' + keys.small } })).resolves.toMatchObject({ ready: false });
    expect(updateOne.mock.calls[1][1].$set.imagorStatus).toBe('failed');
  });
});
