import { createHmac } from 'crypto';
import { Types } from 'mongoose';
import { deliveryConfigVersion, deliveryRows, digestKey, imagorUrls, recoveryKeyForPhoto, sourceKey, withDelivery } from './image-delivery';
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
  it('serves each photo independently without waiting for the entire album cache', async () => {
    const cachedPhoto = readyRow();
    const failedRow = { ...row, _id: new Types.ObjectId(), imageUrl: 'https://originals.example.test/a/failed.jpg', imagorStatus: 'failed', imagorLastError: 'Result Storage verification failed' };
    const [cached, waiting, failed]: any[] = await deliveryRows({} as any, [cachedPhoto, row, failedRow], String(albumId));
    expect(failed.previewUrl).toBe(failedRow.imageUrl);
    expect(failed.viewUrl).toBe(failedRow.imageUrl);
    expect(cached.previewUrl).toBe(cachedPhoto.imagorSmallUrl + '?format=avif');
    expect(cached.deliverySource).toBe('r2');
    expect(cached.viewUrl).toBe(cachedPhoto.imagorViewUrl + '?format=avif');
    expect(waiting.previewUrl).toBe(imagorUrls(row)!.small);
    expect(waiting.deliverySource).toBe('imagor');
    expect(cached.imageUrl).toBe(row.imageUrl);
    expect(cached.imagorSignature).toBeUndefined();
  });
  it('falls back to the original URL for permanent JPEG failures when no watermark is required', () => {
    const failed: any = withDelivery({
      ...row, imagorStatus: 'failed', imagorRecoveryFailedSource: row.imageUrl,
      imagorLastError: 'small: imagor returned HTTP 406: VipsJpeg: premature end of JPEG image',
    }, true);
    expect(failed.previewUrl).toBe(row.imageUrl);
    expect(failed.thumbnailUrl).toBe(row.imageUrl);
    expect(failed.viewUrl).toBe(row.imageUrl);
    expect(failed.deliverySource).toBe('original');
    expect(failed.processingStatus).toBe('failed');
  });
  it('keeps transient failed originals refreshable while displaying their source URL', () => {
    const failed: any = withDelivery({
      ...row, imagorStatus: 'failed', imagorLastError: 'imagor returned HTTP 503: temporarily unavailable',
    }, true);
    expect(failed.previewUrl).toBe(row.imageUrl);
    expect(failed.deliverySource).toBe('imagor');
  });
  it('uses originals for failed free photos even when a visual watermark is configured', () => {
    const branding = { watermarkUrl: 'https://originals.example.test/watermark.png', watermarkOpacity: 0.7 };
    const failed: any = withDelivery({ ...row, imagorStatus: 'failed' }, true, branding);
    expect(failed.previewUrl).toBe(row.imageUrl);
    expect(failed.watermarkApplied).toBe(false);
    expect(failed.deliverySource).toBe('imagor');
  });
  it('keeps original fallback during a retry and for unsupported transforms', () => {
    for (const status of ['pending', 'processing', 'unsupported']) {
      const result: any = withDelivery({ ...row, imagorStatus: status, imagorLastError: 'Result Storage verification failed' }, true);
      expect(result.previewUrl).toBe(row.imageUrl);
      expect(result.viewUrl).toBe(row.imageUrl);
    }
    const unsupported: any = withDelivery({ ...row, imagorStatus: 'unsupported' }, true, { watermarkUrl: 'https://invalid.example.test/watermark.png' });
    expect(unsupported.previewUrl).toBe(row.imageUrl);
  });
  it('does not replace purchase-protected or video previews with originals', () => {
    for (const protection of [{ purchaseRequired: true }, { mediaType: 'video' }]) {
      const protectedRow = { ...row, ...protection, imagorStatus: 'failed', previewUrl: 'https://protected.example.test/preview.jpg' };
      expect((withDelivery(protectedRow, true) as any).previewUrl).toBe(protectedRow.previewUrl);
    }
  });
  it('signs only the deterministic recovery input for a matching source and retains the original download', () => {
    const key = recoveryKeyForPhoto(row)!;
    expect(key).toMatch(/^__airpix_imagor_recovery\/v1\/[a-f0-9]{64}\.jpg$/);
    const recovered = { ...row, imagorRecoverySource: row.imageUrl };
    const branding = { watermarkUrl: 'https://originals.example.test/watermark.png' };
    const urls = imagorUrls(recovered, branding)!;
    expect(urls.small).toContain('/piuphoto/' + key);
    expect(urls.small).toContain('watermark(');
    expect((withDelivery(recovered, true, branding) as any).imageUrl).toBe(row.imageUrl);
    expect(imagorUrls({ ...row, imagorRecoverySource: 'other-source' })!.small).toContain('/piuphoto/a/photo.jpg');
    expect(recoveryKeyForPhoto({ ...row, imageUrl: 'https://evil.test/photo.jpg' })).toBeUndefined();
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
    const failedBranch = findOneAndUpdate.mock.calls[0][0].$or.find((branch: any) => branch.imagorStatus === 'failed');
    expect(failedBranch.imagorLastError.$not).toBeInstanceOf(RegExp);
    expect(failedBranch.imagorLastError.$not.test('small: imagor returned HTTP 406: VipsJpeg: premature end of JPEG image')).toBe(true);
  });
  it('recovers a failed JPEG once, then sends the worker signed recovery transforms', async () => {
    const photo = { ...row, imagorStatus: 'processing', imagorLastError: 'small: imagor returned HTTP 406: VipsJpeg: premature end of JPEG image' };
    const findOneAndUpdate = jest.fn().mockReturnValue({ lean: async () => photo });
    const updateOne = jest.fn().mockResolvedValue({ matchedCount: 1 });
    const recoverImagorJpeg = jest.fn().mockResolvedValue(undefined);
    const service = new ImagorCacheService({ findOneAndUpdate, updateOne } as any, { recoverImagorJpeg } as any);
    const job = await service.claim();
    expect(recoverImagorJpeg).toHaveBeenCalledWith(row.imageUrl, recoveryKeyForPhoto(row));
    expect(job!.urls.small).toContain('/piuphoto/' + recoveryKeyForPhoto(row));
    expect(updateOne.mock.calls[0][1].$set.imagorRecoverySource).toBe(row.imageUrl);
    expect(updateOne.mock.calls[1][1].$set.imagorSource).toBe(row.imageUrl);
    expect(updateOne.mock.calls[1][1].$set.imagorSignature).toBe(job!.urls.small + '|' + job!.urls.view);
  });
  it('records an unsuccessful recovery without looping or overwriting the original', async () => {
    const photo = { ...row, imagorStatus: 'processing', imagorLastError: 'VipsJpeg: Corrupt JPEG data' };
    const findOneAndUpdate = jest.fn().mockReturnValue({ lean: async () => photo });
    const updateOne = jest.fn().mockResolvedValue({ matchedCount: 1 });
    const service = new ImagorCacheService({ findOneAndUpdate, updateOne } as any, {
      recoverImagorJpeg: jest.fn().mockRejectedValue(new Error('decoder rejected image')),
    } as any);
    await expect(service.claim()).resolves.toBeNull();
    expect(updateOne.mock.calls[0][1].$set).toMatchObject({ imagorStatus: 'failed', imagorRecoveryFailedSource: row.imageUrl, imagorLastError: 'JPEG recovery failed: decoder rejected image' });
    expect(updateOne.mock.calls[0][1].$unset.imagorLease).toBe(1);
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
    expect(updateOne.mock.calls[1][1].$set.imagorLastError).toContain('Result Storage verification failed');
  });
  it('publishes individual cache completion and failure updates only to the matching event', async () => {
    const urls = imagorUrls(row)!;
    const token = '12345678-1234-1234-1234-123456789abc';
    const photo = { ...row, imagorLease: token, imagorSource: row.imageUrl, imagorConfig: deliveryConfigVersion(), imagorSignature: urls.small + '|' + urls.view };
    const updateOne = jest.fn().mockResolvedValue({ modifiedCount: 1 });
    const service = new ImagorCacheService({ findOne: jest.fn().mockReturnValue({ lean: async () => photo }), updateOne } as any);
    const own = jest.fn();
    const other = jest.fn();
    const a = service.streamUpdates(String(eventId)).subscribe(own);
    const b = service.streamUpdates(String(new Types.ObjectId())).subscribe(other);
    try {
      const keys = { small: digestKey(urls.small), view: digestKey(urls.view) };
      const result = { small: 'https://result.example.test/' + keys.small, view: 'https://result.example.test/' + keys.view };
      await service.complete(String(row._id) + '~' + token, { success: true, keys, urls: result });
      expect(own).toHaveBeenCalledTimes(1);
      expect(own).toHaveBeenCalledWith({ type: 'gallery', data: { type: 'image_delivery_changed', eventId: String(eventId) } });
      await service.complete(String(row._id) + '~' + token, { success: false, error: 'Result Storage verification failed' });
      expect(own).toHaveBeenCalledTimes(2);
      expect(other).not.toHaveBeenCalled();
    } finally {
      a.unsubscribe();
      b.unsubscribe();
    }
  });
  it('persists the worker failure reason for admin diagnostics', async () => {
    const urls = imagorUrls(row)!;
    const token = '12345678-1234-1234-1234-123456789abc';
    const photo = { ...row, imagorLease: token, imagorSource: row.imageUrl, imagorConfig: deliveryConfigVersion(), imagorSignature: urls.small + '|' + urls.view };
    const updateOne = jest.fn().mockResolvedValue({ modifiedCount: 1 });
    const service = new ImagorCacheService({ findOne: jest.fn().mockReturnValue({ lean: async () => photo }), updateOne } as any);
    const error = 'imagor returned HTTP 403: AccessDenied';
    await expect(service.complete(String(row._id) + '~' + token, { success: false, error })).resolves.toMatchObject({ accepted: true, ready: false });
    expect(updateOne.mock.calls[0][1].$set.imagorLastError).toBe(error);
  });
  it('does not repeatedly retry permanent corrupt-JPEG 406 failures', async () => {
    const urls = imagorUrls(row)!;
    const token = '12345678-1234-1234-1234-123456789abc';
    const photo = { ...row, imagorLease: token, imagorSource: row.imageUrl, imagorConfig: deliveryConfigVersion(), imagorSignature: urls.small + '|' + urls.view };
    const updateOne = jest.fn().mockResolvedValue({ modifiedCount: 1 });
    const service = new ImagorCacheService({ findOne: jest.fn().mockReturnValue({ lean: async () => photo }), updateOne } as any);
    const error = 'small: imagor returned HTTP 406: {\"message\":\"VipsJpeg: premature end of JPEG image\"}';
    await expect(service.complete(String(row._id) + '~' + token, { success: false, error })).resolves.toMatchObject({ accepted: true, ready: false });
    const update = updateOne.mock.calls[0][1];
    expect(update.$set.imagorStatus).toBe('failed');
    expect(update.$set.imagorLastError).toBe(error);
    expect(update.$set.imagorNextAt).toBeUndefined();
    expect(update.$unset.imagorNextAt).toBe(1);
  });
  it('requeues all eligible event photos and returns cache progress', async () => {
    const failureQuery: any = {};
    failureQuery.select = () => failureQuery;
    failureQuery.limit = () => failureQuery;
    failureQuery.lean = async () => [];
    const countDocuments = jest.fn()
      .mockResolvedValueOnce(90)
      .mockResolvedValueOnce(90)
      .mockResolvedValueOnce(0)
      .mockResolvedValueOnce(0);
    const updateMany = jest.fn().mockResolvedValue({ matchedCount: 90, modifiedCount: 90 });
    const aggregate = jest.fn().mockReturnValue({ exec: async () => [{ _id: 'pending', count: 90 }] });
    const service = new ImagorCacheService({ countDocuments, updateMany, aggregate, find: jest.fn().mockReturnValue(failureQuery) } as any);
    const result = await service.recacheEvent(String(eventId));
    expect(updateMany).toHaveBeenCalledTimes(1);
    expect(result.queued).toBe(90);
    expect(result.status).toMatchObject({ eligiblePhotos: 90, ready: 0, remaining: 90, progressPercent: 0 });
    expect(updateMany.mock.calls[0][1].$unset.imagorLastError).toBeUndefined();
    expect(updateMany.mock.calls[0][1].$unset.imagorRecoveryFailedSource).toBe(1);
  });
});
