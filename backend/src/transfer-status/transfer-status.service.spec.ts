import { Types } from 'mongoose';
import { TransferStatusService } from './transfer-status.service';
import { PhotoTransferState } from './entities/photo-transfer-status.entity';

describe('TransferStatusService', () => {
  it('upserts a transfer idempotently and enforces upload permission', async () => {
    const eventId = new Types.ObjectId().toHexString();
    const userId = new Types.ObjectId().toHexString();
    const albumId = new Types.ObjectId().toHexString();
    const result = {
      _id: new Types.ObjectId(),
      eventId,
      photographerId: userId,
      clientTransferId: 'camera-1',
      filename: 'IMG_0001.JPG',
      status: PhotoTransferState.UPLOADING,
      progress: 42,
    };
    const query = {
      populate: jest.fn().mockReturnThis(),
      lean: jest.fn().mockResolvedValue(result),
    };
    const model = {
      findOneAndUpdate: jest.fn().mockReturnValue(query),
    };
    const eventMembers = {
      assertCanUpload: jest.fn().mockResolvedValue({ _id: eventId }),
    };
    const uploadSessionId = new Types.ObjectId();
    const uploadSessions = {
      touchFromTransfer: jest.fn().mockResolvedValue({ _id: uploadSessionId }),
    };
    const service = new TransferStatusService(
      model as never,
      eventMembers as never,
      uploadSessions as never,
    );
    const response = await service.upsert(
      {
        eventId,
        clientTransferId: 'camera-1',
        filename: 'IMG_0001.JPG',
        albumId,
        status: PhotoTransferState.UPLOADING,
        progress: 42,
        bytesSent: 4200,
        bytesTotal: 10000,
        bytesPerSecond: 210000,
      },
      userId,
      'photographer',
    );

    expect(eventMembers.assertCanUpload).toHaveBeenCalledWith(
      eventId,
      userId,
      'photographer',
      albumId,
    );
    expect(model.findOneAndUpdate).toHaveBeenCalledWith(
      expect.objectContaining({
        eventId: expect.any(Types.ObjectId),
        clientTransferId: 'camera-1',
      }),
      expect.objectContaining({
        $set: expect.objectContaining({
          progress: 42,
          bytesSent: 4200,
          bytesTotal: 10000,
        }),
      }),
      expect.objectContaining({
        upsert: true,
        new: true,
      }),
    );
    expect(response.data).toEqual(result);
  });
});
