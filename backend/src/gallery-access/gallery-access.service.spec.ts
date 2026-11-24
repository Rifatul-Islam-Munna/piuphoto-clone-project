import { Types } from 'mongoose';
import { GalleryAccessService } from './gallery-access.service';

describe('GalleryAccessService store protection', () => {
  it('replaces a paid original URL with the store preview URL', async () => {
    const eventId = new Types.ObjectId();
    const imageId = new Types.ObjectId();
    const settings = {
      findOne: jest.fn().mockReturnValue({
        select: jest.fn().mockReturnValue({
          lean: jest.fn().mockResolvedValue({
            enabled: true,
            saleAlbumIds: [],
          }),
        }),
      }),
    };
    const service = new GalleryAccessService(
      {} as never,
      {} as never,
      {} as never,
      settings as never,
      {} as never,
      { get: jest.fn() } as never,
    );

    const result = await service.protectStoreOriginals(String(eventId), [
      {
        _id: imageId,
        imageUrl: 'https://private.example/original.jpg',
        mediaType: 'photo',
        isForSale: true,
      },
    ]);

    expect(result.storeEnabled).toBe(true);
    expect(result.data[0].purchaseRequired).toBe(true);
    expect(result.data[0].imageUrl).toContain('/store/public/preview?');
    expect(result.data[0].imageUrl).not.toContain('private.example');
  });
});

describe('Gallery branding invalidation', () => {
  const env = process.env;
  beforeEach(() => { process.env = { ...env, IMAGOR_ENABLED: 'true', IMAGOR_URL: 'https://imagor.example.test', IMAGOR_SECRET: 'test-only', STORAGE_PUBLIC_URL: 'https://originals.example.test' }; });
  afterEach(() => { process.env = env; });
  it('invalidates only for a changed watermark, including removal', async () => {
    const id = new Types.ObjectId();
    const old = { watermarkUrl: 'https://originals.example.test/logo.png', watermarkOpacity: .7 };
    const updateMany = jest.fn().mockResolvedValue({ modifiedCount: 3 });
    const previous = { _id: id, branding: old };
    const eventModel = {
      db: { collection: jest.fn().mockReturnValue({ updateMany }) },
      findByIdAndUpdate: jest.fn().mockReturnValue({ lean: jest.fn().mockResolvedValue(previous) }),
      findById: jest.fn().mockReturnValue({ lean: jest.fn().mockResolvedValue(previous) }),
    };
    const service = new GalleryAccessService(eventModel as never, {} as never, { create: jest.fn().mockResolvedValue({}) } as never, {} as never, { assertCanManage: jest.fn().mockResolvedValue(undefined) } as never, {} as never);
    await service.updateSettings({ eventId: String(id), branding: { ...old, coverText: 'Changed banner' } });
    expect(updateMany).not.toHaveBeenCalled();
    await service.updateSettings({ eventId: String(id), branding: { ...old, watermarkOpacity: .4 } });
    expect(updateMany).toHaveBeenCalledTimes(1);
    await service.updateSettings({ eventId: String(id), branding: {} });
    expect(updateMany).toHaveBeenCalledTimes(2);
    await expect(service.updateSettings({ eventId: String(id), branding: { watermarkUrl: 'https://external.test/logo.png' } })).rejects.toThrow('Upload the watermark');
  });
});
