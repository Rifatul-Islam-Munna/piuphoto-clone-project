jest.mock('../face-search/face-vector.service', () => ({
  FaceVectorService: class FaceVectorService {},
}));
jest.mock('../face-search/qdrant-face.service', () => ({
  QdrantFaceService: class QdrantFaceService {},
}));

import axios from 'axios';
import { Types } from 'mongoose';
import { EventImageService } from './event-image.service';
import { FalEnhancementJobStatus } from './entities/fal-enhancement-job.entity';

describe('EventImageService FAL webhook', () => {
  const eventId = new Types.ObjectId();
  const uploaderId = new Types.ObjectId();
  const ownerId = new Types.ObjectId();
  const albumId = new Types.ObjectId();
  const eventImageId = new Types.ObjectId();

  const makeService = () => {
    const eventImageModel = {
      findOne: jest.fn(),
      create: jest.fn(),
    };
    const userModel = { findByIdAndUpdate: jest.fn() };
    const falEnhancementJobModel = {
      findOne: jest.fn(),
      findOneAndUpdate: jest.fn(),
      updateOne: jest.fn(),
      create: jest.fn(),
    };
    const configService = {
      get: jest.fn((key: string) => {
        if (key === 'FAL_KEY') return 'test-key';
        if (key === 'FAL_WEBHOOK_URL') {
          return 'https://api.example.com/eventImage/fal-webhook';
        }
        if (key === 'FACE_INDEX_CONCURRENCY') return '1';
        return undefined;
      }),
    };
    const faceVectorService = { vectorsFromUrl: jest.fn().mockResolvedValue([]) };
    const qdrantFaceService = { upsertFaces: jest.fn().mockResolvedValue(undefined) };

    const service = new EventImageService(
      eventImageModel as never,
      {} as never,
      {} as never,
      {} as never,
      userModel as never,
      {} as never,
      falEnhancementJobModel as never,
      configService as never,
      faceVectorService as never,
      qdrantFaceService as never,
    );

    return {
      service,
      eventImageModel,
      userModel,
      falEnhancementJobModel,
    };
  };

  const successfulWebhook = {
    request_id: 'fal-request-1',
    status: 'OK' as const,
    payload: { images: [{ url: 'https://fal.media/enhanced.png' }] },
  };

  it('ignores webhook for another application type', async () => {
    const { service, falEnhancementJobModel } = makeService();

    await expect(
      service.handleFalWebhook('another-app', successfulWebhook),
    ).resolves.toEqual({ received: true, ignored: true });
    expect(falEnhancementJobModel.findOne).not.toHaveBeenCalled();
  });

  it('saves enhanced image using pending job event context', async () => {
    const { service, eventImageModel, falEnhancementJobModel } = makeService();
    const job = {
      _id: new Types.ObjectId(),
      requestId: 'fal-request-1',
      eventId,
      uploaderId,
      ownerId,
      albumId,
      status: FalEnhancementJobStatus.PENDING,
    };
    falEnhancementJobModel.findOne.mockReturnValue({
      exec: jest.fn().mockResolvedValue(job),
    });
    eventImageModel.findOne.mockResolvedValue(null);
    eventImageModel.create.mockResolvedValue({
      _id: eventImageId,
      eventId,
      userTakenBy: uploaderId,
      albumId,
      imageUrl: 'https://fal.media/enhanced.png',
      isEnhanced: true,
    });

    await expect(
      service.handleFalWebhook('puiphoto', successfulWebhook),
    ).resolves.toEqual({
      received: true,
      saved: true,
      eventImageId: String(eventImageId),
    });
    expect(eventImageModel.create).toHaveBeenCalledWith({
      eventId,
      imageUrl: 'https://fal.media/enhanced.png',
      userTakenBy: uploaderId,
      albumId,
      isEnhanced: true,
      falRequestId: 'fal-request-1',
    });
    expect(falEnhancementJobModel.updateOne).toHaveBeenCalledWith(
      { _id: job._id },
      expect.objectContaining({
        $set: { status: FalEnhancementJobStatus.COMPLETED },
      }),
    );
  });

  it('refunds credits once when FAL reports an error', async () => {
    const { service, userModel, falEnhancementJobModel } = makeService();
    const job = {
      _id: new Types.ObjectId(),
      ownerId,
      creditsCharged: 3,
      status: FalEnhancementJobStatus.PENDING,
    };
    falEnhancementJobModel.findOne.mockReturnValue({
      exec: jest.fn().mockResolvedValue(job),
    });
    falEnhancementJobModel.findOneAndUpdate.mockResolvedValue(job);

    await service.handleFalWebhook('puiphoto', {
      request_id: 'fal-request-1',
      status: 'ERROR',
      error: 'generation failed',
    });

    expect(userModel.findByIdAndUpdate).toHaveBeenCalledWith(ownerId, {
      $inc: { credits: 3 },
    });
  });

  it('submits readable queue request and stores correlation context', async () => {
    const { service, falEnhancementJobModel } = makeService();
    jest.spyOn(axios, 'post').mockResolvedValueOnce({
      data: { request_id: 'fal-request-1' },
    });

    await (service as any).submitEnhancementWebhook(
      'https://cdn.example.com/source.jpg',
      undefined,
      {
        eventId: String(eventId),
        uploaderId: String(uploaderId),
        ownerId: String(ownerId),
        albumId: String(albumId),
      },
    );

    const submittedUrl = new URL((axios.post as jest.Mock).mock.calls[0][0]);
    const callbackUrl = new URL(submittedUrl.searchParams.get('fal_webhook')!);
    expect(submittedUrl.origin + submittedUrl.pathname).toBe(
      'https://queue.fal.run/fal-ai/bytedance/seedream/v4/edit',
    );
    expect(callbackUrl.searchParams.get('type')).toBe('puiphoto');
    expect(falEnhancementJobModel.create).toHaveBeenCalledWith(
      expect.objectContaining({
        requestId: 'fal-request-1',
        eventId,
        uploaderId,
        ownerId,
        albumId,
        status: FalEnhancementJobStatus.PENDING,
      }),
    );
  });
});
