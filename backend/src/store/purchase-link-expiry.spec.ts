import { Types } from 'mongoose';
import { StoreService } from './store.service';
import { StoreOrderStatus } from './entities/store-order.entity';
import { purchasedPhotoLinkExpiresAt, PURCHASE_LINK_LIFETIME_HOURS } from './purchase-link-expiry';

describe('purchased-photo 30-day link expiry', () => {
  it('expires 30 full days after payment, not after the email is sent', () => {
    const paid = new Date('2026-11-21T12:34:56.000Z');
    expect(PURCHASE_LINK_LIFETIME_HOURS).toBe(720);
    expect(purchasedPhotoLinkExpiresAt(paid).toISOString()).toBe('2026-12-21T12:34:56.000Z');
  });
  it('issues a 30-day token in the real paid-order flow even for legacy 72-hour event settings', async () => {
    jest.useFakeTimers().setSystemTime(new Date('2026-11-21T12:34:56.000Z'));
    try {
      const _id = new Types.ObjectId();
      const eventId = new Types.ObjectId();
      const pending = { _id, eventId, status: StoreOrderStatus.PENDING };
      let written: any;
      const orderModel = {
        findById: jest.fn(() => ({
          select: () => ({ exec: async () => pending }),
        })),
        findOneAndUpdate: jest.fn((_query, update) => {
          written = update.$set;
          return {
            select: () => ({
              exec: async () => ({ ...pending, ...written }),
            }),
          };
        }),
      };
      const settingsModel = {
        findOneAndUpdate: jest.fn(() => ({
          lean: async () => ({ downloadExpiresHours: 72 }),
        })),
      };
      const service = new StoreService(
        settingsModel as never,
        orderModel as never,
        {} as never, {} as never, {} as never, {} as never,
        { get: jest.fn(() => undefined) } as never,
        { emailConfigured: jest.fn(() => false), whatsappConfigured: jest.fn(() => false) } as never,
      );
      jest.spyOn(service as any, 'sendDelivery').mockResolvedValue(undefined);
      const result = await (service as any).ensurePaid(pending);
      expect(written.status).toBe(StoreOrderStatus.PAID);
      expect(written.downloadExpiresAt.toISOString()).toBe('2026-12-21T12:34:56.000Z');
      expect(result.token).toBeTruthy();
      expect(settingsModel.findOneAndUpdate).not.toHaveBeenCalled();
    } finally {
      jest.useRealTimers();
    }
  });
  it('does not silently create a link from an invalid date', () => {
    expect(() => purchasedPhotoLinkExpiresAt(new Date('invalid'))).toThrow();
  });
});
