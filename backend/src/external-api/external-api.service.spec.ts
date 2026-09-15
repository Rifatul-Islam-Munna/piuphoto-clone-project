import { Types } from 'mongoose';
import { ExternalApiService } from './external-api.service';

describe('ExternalApiService tenant isolation', () => {
  it('rejects an API key scoped to a different event', async () => {
    const eventA = new Types.ObjectId();
    const eventB = new Types.ObjectId();
    const credential = {
      _id: new Types.ObjectId(),
      userId: new Types.ObjectId(),
      scopes: ['upload:write'],
      eventIds: [eventA],
      hourlyQuota: 1000,
      save: jest.fn().mockResolvedValue(undefined),
    };
    const credentials = {
      findOne: jest.fn().mockReturnValue({
        select: jest.fn().mockReturnValue({
          exec: jest.fn().mockResolvedValue(credential),
        }),
      }),
    };
    const usage = {
      findOneAndUpdate: jest.fn().mockReturnValue({
        lean: jest.fn().mockResolvedValue({ count: 1 }),
      }),
    };    const members = { assertCanAccess: jest.fn() };
    const auditLogs = { create: jest.fn() };
    const service = new ExternalApiService(
      credentials as never,
      {} as never,
      {} as never,
      usage as never,
      auditLogs as never,
      {} as never,
      {} as never,
      members as never,
    );

    await expect(
      service.authenticate('secret-key', 'upload:write', String(eventB)),
    ).rejects.toThrow('API key is not scoped to this event');
    expect(members.assertCanAccess).not.toHaveBeenCalled();
    expect(credential.save).not.toHaveBeenCalled();
  });
});


describe('ExternalApiService webhook recovery', () => {
  it('requeues one dead delivery instead of creating a new delivery', async () => {
    const eventId = new Types.ObjectId();
    const deliveryId = new Types.ObjectId();
    const updated = { _id: deliveryId, eventId, status: 'pending', attempts: 0 };
    const deliveries = {
      findById: jest.fn().mockReturnValue({
        select: jest.fn().mockReturnValue({
          lean: jest.fn().mockResolvedValue({ _id: deliveryId, eventId, status: 'dead' }),
        }),
      }),
      findByIdAndUpdate: jest.fn().mockReturnValue({
        lean: jest.fn().mockResolvedValue(updated),
      }),
      insertMany: jest.fn(),
    };
    const members = { assertCanManage: jest.fn().mockResolvedValue(undefined) };
    const service = new ExternalApiService(
      {} as never, {} as never, deliveries as never, {} as never,
      {} as never, {} as never, {} as never, members as never,
    );
    const result = await service.retryWebhookDelivery(
      String(deliveryId),
      String(new Types.ObjectId()),
    );
    expect(result.data).toBe(updated);
    expect(members.assertCanManage).toHaveBeenCalledWith(
      String(eventId),
      expect.any(String),
      undefined,
    );
    expect(deliveries.findByIdAndUpdate).toHaveBeenCalledTimes(1);
    expect(deliveries.insertMany).not.toHaveBeenCalled();
  });
});
