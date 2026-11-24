import { Types } from 'mongoose';
import { deliveryConfigVersion, deliveryRows, digestKey, imagorUrls, withDelivery, nativeWatermarkFilter, invalidateEventWatermark, imagorStorePreview } from './image-delivery';
import { ImagorCacheService } from './imagor-cache.service';

const env = process.env;
const eventId = new Types.ObjectId();
const row = { _id: new Types.ObjectId(), eventId, imageUrl: 'https://originals.example.test/a.jpg', mediaType: 'photo' };
const brand = { watermarkUrl: 'https://originals.example.test/logo.png', watermarkPosition: 'bottom_right', watermarkOpacity: .7, watermarkScale: 24 };
const db = (branding: any) => ({ collection: jest.fn().mockReturnValue({ find: jest.fn().mockReturnValue({ toArray: jest.fn().mockResolvedValue([{ _id: eventId, branding }]) }) }) });
const cached = (branding?: typeof brand) => {
  const urls = imagorUrls(row, branding)!;
  return { ...row, imagorStatus: 'ready', imagorConfig: deliveryConfigVersion(), imagorSource: row.imageUrl, imagorSignature: urls.small + '|' + urls.view,
    imagorSmallUrl: 'https://result.example.test/' + digestKey(urls.small), imagorViewUrl: 'https://result.example.test/' + digestKey(urls.view) };
};
beforeEach(() => { process.env = { ...env, IMAGOR_ENABLED: 'true', IMAGOR_URL: 'https://imagor.example.test', IMAGOR_SECRET: 'test-only', IMAGOR_SIGNER_TYPE: 'sha256', IMAGOR_SIGNER_TRUNCATE: '40', STORAGE_PUBLIC_URL: 'https://originals.example.test', IMAGOR_RESULT_PUBLIC_URL: 'https://result.example.test' }; });
afterEach(() => { process.env = env; });

describe('Native Imagor watermarks', () => {
  it('uses the existing routed asset, native position, opacity and scale', () => {
    const asset = Buffer.from('piuphoto/logo.png').toString('base64url');
    expect(nativeWatermarkFilter(brand)).toBe('watermark(b64:' + asset + ',right,bottom,30,24,24)');
    expect(nativeWatermarkFilter({ ...brand, watermarkPosition: 'tile', watermarkOpacity: 1, watermarkScale: 40 })).toContain(',repeat,repeat,0,40,40)');
    expect(nativeWatermarkFilter({ ...brand, watermarkPosition: '__proto__' })).toBe(nativeWatermarkFilter(brand));
    expect(imagorUrls(row, { ...brand, watermarkUrl: 'https://evil.test/logo.png' })).toBeUndefined();
  });
  it('signs only derivatives and leaves original imageUrl unchanged', () => {
    const marked = imagorUrls(row, brand)!;
    const plain = imagorUrls(row)!;
    for (const kind of ['thumbnail', 'small', 'view'] as const) {
      expect(marked[kind]).toContain(nativeWatermarkFilter(brand));
      expect(digestKey(marked[kind])).not.toEqual(digestKey(plain[kind]));
    }
    expect(withDelivery(row, false, brand)).toMatchObject({ imageUrl: row.imageUrl, previewUrl: marked.small, watermarkApplied: true });
  });
  it('never serves a stale clean or previously watermarked cached preview', async () => {
    const model = { distinct: jest.fn().mockResolvedValue([]), db: db(brand) };
    expect((await deliveryRows(model as any, [cached()]))[0]).toMatchObject({ deliverySource: 'imagor', previewUrl: imagorUrls(row, brand)!.small });
    const ready = cached(brand);
    expect((await deliveryRows(model as any, [ready]))[0]).toMatchObject({ deliverySource: 'r2', previewUrl: ready.imagorSmallUrl + '?format=avif', imageUrl: row.imageUrl });
    const next = { ...brand, watermarkOpacity: .4 };
    expect(withDelivery(ready, true, next)).toMatchObject({ deliverySource: 'imagor', previewUrl: imagorUrls(row, next)!.small });
    expect(withDelivery(ready, true, {})).toMatchObject({ deliverySource: 'imagor', watermarkApplied: false, previewUrl: imagorUrls(row)!.small });
  });
  it('prewarms the current watermark and rejects stale callbacks', async () => {
    const changed = { ...brand, watermarkPosition: 'top_left' };
    const updateOne = jest.fn().mockResolvedValue({ matchedCount: 1, modifiedCount: 1 });
    const service = new ImagorCacheService({ db: db(changed), updateOne,
      findOneAndUpdate: jest.fn().mockReturnValue({ lean: async () => row }),
      findOne: jest.fn().mockReturnValue({ lean: async () => cached(brand) }),
    } as any);
    const job = await service.claim();
    const urls = imagorUrls(row, changed)!;
    expect(job!.urls).toEqual({ small: urls.small, view: urls.view });
    expect(await service.complete(String(row._id) + '~12345678-1234-1234-1234-123456789abc', { success: true })).toEqual({ accepted: true, ready: false });
    expect(updateOne.mock.calls[1][1].$set.imagorStatus).toBe('pending');
  });
  it('requeues derivatives for just this event, fencing previous leases', async () => {
    const updateMany = jest.fn().mockResolvedValue({ modifiedCount: 2 });
    await invalidateEventWatermark({ db: { collection: () => ({ updateMany }) } } as any, String(eventId));
    expect(updateMany).toHaveBeenCalledWith(expect.objectContaining({ eventId, mediaType: { $ne: 'video' } }), {
      $set: { imagorStatus: 'pending' }, $unset: { imagorLease: 1, imagorNextAt: 1, imagorAttempts: 1 },
    });
  });
  it('reuses warmed store previews or creates a smaller native derivative', () => {
    expect(imagorStorePreview(row, brand, { previewMaxWidth: 1200, previewQuality: 64 })).toBe(imagorUrls(row, brand)!.small);
    expect(imagorStorePreview(row, brand, { previewMaxWidth: 2400, previewQuality: 80 })).toBe(imagorUrls(row, brand)!.view);
    expect(imagorStorePreview(row, brand, { previewMaxWidth: 400, previewQuality: 50 })).toContain('/400x400/');
    expect(imagorStorePreview(row, undefined, {})).toContain('text(b64:UFJFVklFVw');
    expect(imagorStorePreview(row, undefined, { watermarkedPreview: false })).not.toContain('text(');
  });
});
