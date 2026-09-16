import axios from 'axios';
import { Types } from 'mongoose';
import { StoreService } from './store.service';
import { StoreOrderStatus } from './entities/store-order.entity';

describe('StoreService checkout idempotency', () => {
  afterEach(() => jest.restoreAllMocks());

  it('reuses the same pending Stripe checkout for a retried request', async () => {
    const eventId = new Types.ObjectId();
    const photoA = new Types.ObjectId();
    const photoB = new Types.ObjectId();
    const settings = {
      enabled: true,
      currency: 'USD',
      singlePhotoPrice: 5,
      bundlePrice: 0,
      bundleMinPhotos: 10,
      downloadExpiresHours: 72,
      saleAlbumIds: [],
    };
    const settingsModel = {
      findOneAndUpdate: jest.fn().mockReturnValue({
        select: jest.fn().mockReturnThis(),
        lean: jest.fn().mockResolvedValue(settings),
      }),
    };
    const images = {
      find: jest.fn().mockReturnValue({
        select: jest
          .fn()
          .mockReturnValue({
            lean: jest
              .fn()
              .mockResolvedValue([{ _id: photoA }, { _id: photoB }]),
          }),
      }),
    };
    const order = {
      _id: new Types.ObjectId(),
      eventId,
      imageIds: [photoA, photoB],
      email: 'guest@example.com',
      amount: 10,
      currency: 'USD',
      orderNo: 'ORD-RETRY',
      status: StoreOrderStatus.PENDING,
      stripeSessionId: 'cs_test_same',
      stripeCheckoutUrl: 'https://checkout.stripe.test/session',
    };
    const orders = {
      findOneAndUpdate: jest.fn().mockReturnValue({
        exec: jest.fn().mockResolvedValue(order),
      }),
    };
    const service = new StoreService(
      settingsModel as never,
      orders as never,
      {} as never,
      images as never,
      {} as never,
      {} as never,
      { get: jest.fn() } as never,
      {
        emailConfigured: jest.fn().mockReturnValue(false),
        whatsappConfigured: jest.fn().mockReturnValue(false),
      } as never,
    );
    const stripe = jest.spyOn(axios, 'post');
    const result = await service.checkout({
      eventId: String(eventId),
      imageIds: [String(photoA), String(photoB)],
      email: 'guest@example.com',
      idempotencyKey: 'checkout-retry-1',
    });

    expect(result.idempotent).toBe(true);
    expect(result.sessionId).toBe('cs_test_same');
    expect(result.url).toBe('https://checkout.stripe.test/session');
    expect(stripe).not.toHaveBeenCalled();
  });
});

describe('StoreService without Stripe webhook secret', () => {
  it('falls back to Stripe API reconciliation instead of failing', async () => {
    const service = new StoreService(
      {} as never,
      {} as never,
      {} as never,
      {} as never,
      {} as never,
      {} as never,
      { get: jest.fn().mockReturnValue(undefined) } as never,
      {
        emailConfigured: jest.fn().mockReturnValue(false),
        whatsappConfigured: jest.fn().mockReturnValue(false),
      } as never,
    );

    await expect(service.webhook(undefined, undefined, {})).resolves.toEqual({
      received: true,
      verified: false,
      mode: 'stripe-api-reconciliation',
    });
  });
});
