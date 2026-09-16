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
