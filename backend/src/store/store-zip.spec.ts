import { createHash } from 'node:crypto';
import { Readable, Writable } from 'node:stream';
import { Types } from 'mongoose';
import { StoreService } from './store.service';

const orderId = new Types.ObjectId();
const eventId = new Types.ObjectId();
const photoId = new Types.ObjectId();
const validToken = 'secure-purchase-token';

function fixture(authorized = true, fileAvailable = true) {
  const order = {
    _id: orderId,
    eventId,
    imageIds: [photoId],
    orderNo: 'ORD-PAID-1',
  };
  const orders = {
    findOne: jest.fn((filter: any) => ({
      select: () => ({
        lean: async () =>
          authorized &&
          filter.status === 'paid' &&
          filter.downloadTokenHash === createHash('sha256').update(validToken).digest('hex')
            ? order : null,
      }),
    })),
  };
  const photos = {
    find: jest.fn(() => ({
      select: () => ({
        lean: async () => fileAvailable
          ? [{ _id: photoId, imageUrl: 'https://storage.example.test/gallery/photo1.jpg', mediaType: 'photo' }]
          : [],
      }),
    })),
  };
  const storage = {
    canStreamStoredUrl: jest.fn((url: string) => url.startsWith('https://storage.example.test')),
    openStoredUrl: jest.fn(async () => Readable.from([Buffer.from('original-photo-data')])),
  };
  const service = new StoreService(
    {} as never, orders as never, {} as never, photos as never,
    {} as never, {} as never, {} as never, {} as never, storage as never,
  );
  const chunks: Buffer[] = [];
  const response: any = new Writable({
    write(chunk, _encoding, callback) {
      chunks.push(Buffer.from(chunk));
      callback();
    },
  });
  response.status = jest.fn().mockReturnValue(response);
  response.setHeader = jest.fn();
  return { service, response, chunks, storage, orders, photos };
}

describe('post-payment email and direct download links', () => {
  it('sends the same secure paid order URL used after checkout to buyer email', async () => {
    const paidOrder = {
      _id: orderId,
      orderNo: 'ORD-PAID-1',
      eventId,
      imageIds: [photoId],
      email: 'guest@example.test',
      downloadExpiresAt: new Date('2026-11-24T10:00:00Z'),
    };
    const orders = {
      findOneAndUpdate: jest.fn().mockReturnValue({
        exec: async () => paidOrder,
      }),
      updateOne: jest.fn().mockResolvedValue({ modifiedCount: 1 }),
    };
    const events = {
      findById: jest.fn().mockReturnValue({
        select: () => ({ lean: async () => ({ title: 'Nikos Wedding' }) }),
      }),
    };
    const notifier = {
      emailConfigured: jest.fn().mockReturnValue(true),
      whatsappConfigured: jest.fn().mockReturnValue(false),
      sendStoreDelivery: jest.fn().mockResolvedValue(undefined),
    };
    const config = {
      get: jest.fn((name: string) => name === 'PUBLIC_APP_URL' ? 'https://airpix.app' : ''),
    };
    const service = new StoreService(
      {} as never, orders as never, events as never, {} as never,
      {} as never, {} as never, config as never, notifier as never,
    );
    await (service as any).sendDelivery(paidOrder, validToken);
    expect(notifier.sendStoreDelivery).toHaveBeenCalledWith(expect.objectContaining({
      email: 'guest@example.test',
      eventTitle: 'Nikos Wedding',
      orderNo: 'ORD-PAID-1',
      expiresAt: new Date('2026-11-24T10:00:00Z'),
      link: `https://airpix.app/#/store/order/${orderId}?token=${encodeURIComponent(validToken)}`,
    }));
    expect(orders.updateOne).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ $set: expect.objectContaining({ deliverySentAt: expect.any(Date) }) }),
    );
  });

  it('does not mark delivery complete when SMTP fails; a retry can send the link', async () => {
    const paidOrder = {
      _id: orderId,
      orderNo: 'ORD-PAID-2',
      eventId,
      imageIds: [photoId],
      email: 'guest@example.test',
    };
    const orders = {
      findOneAndUpdate: jest.fn().mockReturnValue({ exec: async () => paidOrder }),
      updateOne: jest.fn().mockResolvedValue({ modifiedCount: 1 }),
    };
    const events = { findById: jest.fn().mockReturnValue({
      select: () => ({ lean: async () => ({ title: 'Nikos Wedding' }) }),
    }) };
    const notifier = {
      emailConfigured: jest.fn().mockReturnValue(true),
      whatsappConfigured: jest.fn().mockReturnValue(false),
      sendStoreDelivery: jest.fn().mockRejectedValue(new Error('SMTP temporarily unavailable')),
    };
    const service = new StoreService(
      {} as never, orders as never, events as never, {} as never,
      {} as never, {} as never,
      { get: jest.fn().mockReturnValue('https://airpix.app') } as never,
      notifier as never,
    );
    await expect((service as any).sendDelivery(paidOrder, validToken))
      .resolves.toBeUndefined();
    expect(orders.updateOne).not.toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ $set: expect.objectContaining({ deliverySentAt: expect.any(Date) }) }),
    );
    expect(orders.updateOne).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ $set: expect.objectContaining({
        deliveryError: expect.stringContaining('SMTP'),
      }) }),
    );
  });
});

describe('secure full-resolution purchased-order ZIP', () => {
  it('streams only paid order photos as a ZIP; no full-gallery memory buffering', async () => {
    const { service, response, chunks, storage } = fixture();
    await service.downloadPurchasedZip(String(orderId), validToken, response);
    const archive = Buffer.concat(chunks);
    expect(archive.subarray(0, 2).toString()).toBe('PK');
    expect(archive.includes(Buffer.from('original-photo-data'))).toBe(true);
    expect(response.setHeader).toHaveBeenCalledWith('Content-Type', 'application/zip');
    expect(response.setHeader).toHaveBeenCalledWith(
      'Content-Disposition', expect.stringContaining('attachment; filename="AirPix-ORD-PAID-1.zip"'),
    );
    expect(storage.openStoredUrl).toHaveBeenCalledTimes(1);
  });

  it('rejects invalid purchase tokens and expired/unpaid orders', async () => {
    const { service, response, storage } = fixture();
    await expect(service.downloadPurchasedZip(String(orderId), 'wrong-token', response))
      .rejects.toThrow('invalid or expired');
    expect(storage.openStoredUrl).not.toHaveBeenCalled();
  });

  it('rejects missing originals before sending download headers', async () => {
    const { service, response, storage } = fixture(true, false);
    await expect(service.downloadPurchasedZip(String(orderId), validToken, response))
      .rejects.toThrow('cannot be archived');
    expect(response.setHeader).not.toHaveBeenCalled();
    expect(storage.openStoredUrl).not.toHaveBeenCalled();
  });

  it('does not redirect to arbitrary external storage URLs', async () => {
    const { service, response, storage } = fixture();
    storage.canStreamStoredUrl.mockReturnValue(false);
    await expect(service.downloadPurchasedZip(String(orderId), validToken, response))
      .rejects.toThrow('cannot be archived');
    expect(storage.openStoredUrl).not.toHaveBeenCalled();
  });
});
