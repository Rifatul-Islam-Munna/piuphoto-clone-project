import 'reflect-metadata';
import axios from 'axios';
import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';
import { Types } from 'mongoose';
import { StoreSettingsDto } from './dto/store.dto';
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
        select: jest.fn().mockReturnValue({
          lean: jest.fn().mockResolvedValue([{ _id: photoA }, { _id: photoB }]),
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

describe('StoreService planner settings response', () => {
  it('does not expose Mongo metadata that the settings DTO rejects', async () => {
    const eventId = String(new Types.ObjectId());
    const storedSettings = {
      _id: new Types.ObjectId(),
      property_id: 'virtual-metadata',
      eventId: new Types.ObjectId(eventId),
      createdAt: new Date(),
      updatedAt: new Date(),
      __v: 0,
      enabled: true,
      currency: 'USD',
      singlePhotoPrice: 5,
      wholeEventPrice: 100,
      bundlePrice: 20,
      bundleMinPhotos: 5,
      downloadExpiresHours: 72,
      watermarkedPreview: true,
      previewMaxWidth: 1200,
      previewQuality: 64,
      useCustomStripe: false,
      coverTitle: 'Conference Store',
      coverImageUrl: 'https://example.com/cover.jpg',
      saleAlbumIds: [],
      stripePublishableKey: 'pk_test_example',
      stripeSecretCipher: 'encrypted',
    };
    const settingsModel = {
      findOneAndUpdate: jest.fn().mockReturnValue({
        select: jest.fn().mockReturnThis(),
        lean: jest.fn().mockResolvedValue(storedSettings),
      }),
    };
    const members = {
      assertCanManage: jest.fn().mockResolvedValue(undefined),
    };
    const service = new StoreService(
      settingsModel as never,
      {} as never,
      {} as never,
      {} as never,
      {} as never,
      members as never,
      { get: jest.fn() } as never,
      {
        emailConfigured: jest.fn().mockReturnValue(false),
        whatsappConfigured: jest.fn().mockReturnValue(false),
      } as never,
    );

    const result = await service.settingsForPlanner(
      eventId,
      String(new Types.ObjectId()),
      'photographer',
    );

    expect(result.data).toMatchObject({
      enabled: true,
      coverTitle: 'Conference Store',
      coverImageUrl: 'https://example.com/cover.jpg',
      stripePublishableKey: 'pk_test_example',
      customStripeConfigured: true,
    });
    expect(result.data).not.toHaveProperty('property_id');
    expect(result.data).not.toHaveProperty('_id');
    expect(result.data).not.toHaveProperty('eventId');
    expect(result.data).not.toHaveProperty('createdAt');
    expect(result.data).not.toHaveProperty('updatedAt');
    expect(result.data).not.toHaveProperty('__v');
    expect(result.data).not.toHaveProperty('stripeSecretCipher');
  });
});

describe('StoreSettingsDto backwards compatibility', () => {
  it('accepts response-only Stripe status flags from cached clients', async () => {
    const dto = plainToInstance(StoreSettingsDto, {
      eventId: String(new Types.ObjectId()),
      enabled: true,
      customStripeConfigured: true,
      customStripeWebhookConfigured: true,
      stripePublishableKey: 'pk_test_example',
      stripeSecretKey: '',
      stripeWebhookSecret: '',
    });

    const errors = await validate(dto, {
      whitelist: true,
      forbidNonWhitelisted: true,
    });

    expect(errors).toHaveLength(0);
  });
});

describe('StoreService custom Stripe validation', () => {
  it('rejects publishable and secret keys from different Stripe modes', async () => {
    const eventId = String(new Types.ObjectId());
    const settingsModel = {
      findOneAndUpdate: jest.fn().mockReturnValue({
        select: jest.fn().mockReturnThis(),
        lean: jest.fn().mockResolvedValue({ useCustomStripe: false }),
      }),
    };
    const members = {
      assertCanManage: jest.fn().mockResolvedValue(undefined),
    };
    const service = new StoreService(
      settingsModel as never,
      {} as never,
      {} as never,
      {} as never,
      {} as never,
      members as never,
      { get: jest.fn().mockReturnValue(undefined) } as never,
      {
        emailConfigured: jest.fn().mockReturnValue(false),
        whatsappConfigured: jest.fn().mockReturnValue(false),
      } as never,
    );

    await expect(
      service.updateSettings(
        {
          eventId,
          useCustomStripe: true,
          stripePublishableKey: 'pk_test_example',
          stripeSecretKey: 'sk_live_example',
        },
        String(new Types.ObjectId()),
        'photographer',
      ),
    ).rejects.toThrow(
      'Stripe publishable and secret keys must both use test mode or both use live mode',
    );
  });
});
