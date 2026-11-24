jest.mock('../face-search/face-vector.service', () => ({
  FaceVectorService: class FaceVectorService {},
}));
jest.mock('../face-search/qdrant-face.service', () => ({
  QdrantFaceService: class QdrantFaceService {},
}));

import axios from 'axios';
import { Logger } from '@nestjs/common';
import { Types } from 'mongoose';
import { EventImageService } from './event-image.service';
import { FalEnhancementJobStatus } from './entities/fal-enhancement-job.entity';
import { buildEnhancementPrompt, resolvePhotoFinishingOptions } from './enhancement-prompts';

describe('EventImageService FAL webhook', () => {
  afterEach(() => jest.restoreAllMocks());

  const eventId = new Types.ObjectId();
  const uploaderId = new Types.ObjectId();
  const ownerId = new Types.ObjectId();
  const albumId = new Types.ObjectId();
  const eventImageId = new Types.ObjectId();

  const makeService = () => {
    const eventImageModel = {
      findOne: jest.fn(),
      create: jest.fn(),
      updateOne: jest.fn().mockResolvedValue({ modifiedCount: 1 }),
    };
    const userModel = {
      findByIdAndUpdate: jest.fn(),
      findOneAndUpdate: jest.fn().mockReturnValue({
        select: jest.fn().mockReturnValue({ lean: jest.fn().mockResolvedValue({ _id: ownerId }) }),
      }),
    };
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

    const output = { save: jest.fn().mockResolvedValue('https://r2.example.com/enhanced.png') };
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
      {} as never,
      { markPublication: jest.fn() } as never,
      {} as never,
      { onPhotoIndexed: jest.fn().mockResolvedValue(undefined) } as never,
      { queueAnalysis: jest.fn() } as never,
      { registerIncoming: jest.fn().mockResolvedValue(undefined) } as never,
      { publish: jest.fn().mockResolvedValue(0) } as never,
      output as never,
    );

    return {
      service,
      eventImageModel,
      userModel,
      falEnhancementJobModel,
      output,
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
    const { service, eventImageModel, falEnhancementJobModel, output } = makeService();
    const job = {
      _id: new Types.ObjectId(),
      requestId: 'fal-request-1',
      eventId,
      uploaderId,
      ownerId,
      albumId,
      sourceImageUrl: 'https://r2.example.com/original.jpg',
      photoFinishing: { exposure: 95, shadows: 95, color: 60, lowLight: true },
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
      imageUrl: 'https://r2.example.com/enhanced.png',
      isEnhanced: true,
    });

    await expect(
      service.handleFalWebhook('puiphoto', successfulWebhook),
    ).resolves.toEqual({
      received: true,
      saved: true,
      eventImageId: String(eventImageId),
    });
    expect(output.save).toHaveBeenCalledWith(job.sourceImageUrl, 'https://fal.media/enhanced.png', undefined, 'fal-request-1', job.photoFinishing);
    expect(eventImageModel.create).toHaveBeenCalledWith({
      eventId,
      imageUrl: 'https://r2.example.com/enhanced.png',
      userTakenBy: uploaderId,
      albumId,
      isEnhanced: true,
      isPublished: true,
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
        isPublished: true,
        photoFinishing: resolvePhotoFinishingOptions({ aiPreset: 'low_light' }),
      },
    );

    const submittedUrl = new URL((axios.post as jest.Mock).mock.calls[0][0]);
    const callbackUrl = new URL(submittedUrl.searchParams.get('fal_webhook')!);
    expect(submittedUrl.origin + submittedUrl.pathname).toBe(
      'https://queue.fal.run/fal-ai/bytedance/seedream/v4/edit',
    );
    expect(callbackUrl.searchParams.get('type')).toBe('puiphoto');
    expect((axios.post as jest.Mock).mock.calls[0][1].prompt).toContain('clear, visible improvement');
    expect((axios.post as jest.Mock).mock.calls[0][1].prompt).not.toContain('Preserve the original image as much as possible');
    expect(falEnhancementJobModel.create).toHaveBeenCalledWith(
      expect.objectContaining({
        requestId: 'fal-request-1',
        eventId,
        uploaderId,
        ownerId,
        albumId,
        photoFinishing: { exposure: 95, shadows: 95, color: 60, lowLight: true },
        status: FalEnhancementJobStatus.PENDING,
      }),
    );
  });

  it('uses the same complete prompt and image settings for synchronous and queued editing', async () => {
    const { service } = makeService();
    const post = jest.spyOn(axios, 'post')
      .mockResolvedValueOnce({ data: { images: [{ url: 'https://fal.media/enhanced.png' }] } })
      .mockResolvedValueOnce({ data: { request_id: 'fal-request-2' } });
    const source = 'https://cdn.example.com/source.jpg';
    const prompt = buildEnhancementPrompt({ aiPreset: 'portrait' }, 'Skin beautification: Keep freckles');

    await (service as any).enhanceImage(source, prompt);
    await (service as any).submitEnhancementWebhook(source, prompt, {
      eventId: String(eventId), uploaderId: String(uploaderId), ownerId: String(ownerId), isPublished: false,
    });

    expect(post.mock.calls[0][1]).toEqual(post.mock.calls[1][1]);
    expect(post.mock.calls[0][1]).toEqual(expect.objectContaining({
      prompt, image_urls: [source], image_size: 'auto_4K', num_images: 1,
      max_images: 1, enable_safety_checker: true, enhance_prompt_mode: 'standard',
    }));
  });

  it.each([false, true])('retains the subscription gate for per-photo tasks (custom enhancer: %s)', async hasCustomEnhancer => {
    const { service, output } = makeService();
    jest.spyOn(service as any, 'getOwnerPlanMeta').mockResolvedValue({ credits: 10, hasCustomEnhancer });
    jest.spyOn(service as any, 'useFalWebhook').mockReturnValue(false);
    const enhance = jest.spyOn(service as any, 'enhanceImage').mockResolvedValue('https://fal.media/enhanced.png');
    const settings = { aiPreset: 'sports' as const, aiPrompt: 'Keep the team colors' };
    const request = 'Skin beautification: Keep freckles';

    await (service as any).tryEnhanceForOwner(
      'https://cdn.example.com/source.jpg', String(eventId), String(uploaderId), String(ownerId),
      undefined, request, false, undefined, settings,
    );

    expect(enhance).toHaveBeenCalledWith(
      'https://cdn.example.com/source.jpg',
      buildEnhancementPrompt(settings, hasCustomEnhancer ? request : undefined),
    );
    expect(output.save).toHaveBeenCalledWith(
      'https://cdn.example.com/source.jpg', 'https://fal.media/enhanced.png', undefined, undefined,
      resolvePhotoFinishingOptions(settings, hasCustomEnhancer ? request : undefined),
    );
  });
});


describe('EventImageService upload idempotency', () => {
  it('returns the existing photo for the same client transfer id', async () => {
    const eventId = new Types.ObjectId();
    const userId = new Types.ObjectId();
    const existing = { _id: new Types.ObjectId(), eventId, clientTransferId: 'capture-1' };
    const eventImageModel = {
      findOne: jest.fn().mockReturnValue({ exec: jest.fn().mockResolvedValue(existing) }),
      create: jest.fn(),
    };
    const eventModel = {
      findById: jest.fn().mockReturnValue({
        select: jest.fn().mockReturnValue({
          lean: jest.fn().mockResolvedValue({ _id: eventId, userId, title: 'Event' }),
        }),
      }),
    };
    const members = { assertCanUpload: jest.fn().mockResolvedValue(undefined) };
    const output = { save: jest.fn().mockResolvedValue('https://r2.example.com/enhanced.png') };
    const service = new EventImageService(
      eventImageModel as never, eventModel as never, {} as never, {} as never,
      {} as never, {} as never, {} as never, { get: jest.fn() } as never,
      {} as never, {} as never, members as never, {} as never, {} as never,      {} as never, {} as never, {} as never, {} as never,
      output as never,
    );
    const result = await service.create({
      eventId: String(eventId),
      imageUrl: 'https://cdn.example/photo.jpg',
      isEnhanced: false,
      clientTransferId: 'capture-1',
    }, String(userId));
    expect(result.idempotent).toBe(true);
    expect(result.data).toBe(existing);
    expect(eventImageModel.create).not.toHaveBeenCalled();
    expect(members.assertCanUpload).toHaveBeenCalled();
  });
});

describe('EventImageService camera upload confirmation', () => {
  function makeService(autoEnhanceImages = true) {
    const eventId = new Types.ObjectId();
    const userId = new Types.ObjectId();
    const event = { _id: eventId, userId, autoEnhanceImages };
    const original = { _id: new Types.ObjectId(), eventId, isPublished: true, imageUrl: 'https://images.example/shot.jpg' };
    const enhanced = { _id: new Types.ObjectId(), eventId, isPublished: true };
    const model = {
      findOne: jest.fn().mockReturnValue({ exec: jest.fn().mockResolvedValue(null) }),
      findById: jest.fn().mockResolvedValue(original),
      exists: jest.fn().mockResolvedValue(null),
      create: jest.fn().mockResolvedValue(original),
      insertMany: jest.fn().mockImplementation(async (docs) => docs.map(doc => ({ ...doc, _id: new Types.ObjectId() }))),
      updateOne: jest.fn().mockResolvedValue({ modifiedCount: 1 }),
    };
    const publish = jest.fn().mockResolvedValue(0);
    const service = new EventImageService(
      model as never, {} as never, {} as never, {} as never, {} as never,
      {} as never, {} as never, {} as never, {} as never, {} as never,
      { assertCanUpload: jest.fn().mockResolvedValue(undefined) } as never,
      {} as never, {} as never, {} as never, {} as never, {} as never,
      { publish } as never,
      { save: jest.fn() } as never,
    );
    jest.spyOn(service as any, 'assertCanUseEvent').mockResolvedValue(event);
    jest.spyOn(service as any, 'assertEventUploadLimit').mockResolvedValue(undefined);
    jest.spyOn(service as any, 'resolvePublishPolicy').mockResolvedValue('auto_upload');
    const automate = jest.spyOn(service as any, 'queuePhotoAutomation').mockImplementation(() => undefined);
    let finishEnhancement: (value: unknown) => void;
    let rejectEnhancement: (error: Error) => void;
    const pending = new Promise((resolve, reject) => {
      finishEnhancement = resolve;
      rejectEnhancement = reject;
    });
    const enhance = jest.spyOn(service as any, 'tryEnhanceForOwner').mockReturnValue(pending);
    return {
      service, model, original, enhanced, automate, enhance, publish,
      finishEnhancement, rejectEnhancement, userId,
      dto: { eventId: String(eventId), imageUrl: 'https://images.example/shot.jpg', clientTransferId: 'camera-shot-1' },
    };
  }

  afterEach(() => jest.restoreAllMocks());

  it('confirms the saved photo while automatic enhancement is still blocked', async () => {
    const fixture = makeService();
    const response = fixture.service.create(fixture.dto, String(fixture.userId));
    try {
      const result = await Promise.race([
        response,
        new Promise((resolve) => setTimeout(() => resolve('still waiting for AI'), 20)),
      ]);
      expect(result).toMatchObject({ data: fixture.original });
      expect(fixture.enhance).toHaveBeenCalledTimes(1);
    } finally {
      fixture.finishEnhancement(fixture.enhanced);
      await response;
      await new Promise(setImmediate);
    }
    expect(fixture.automate).toHaveBeenCalledWith(fixture.enhanced);
    expect(fixture.publish).toHaveBeenCalledWith(
      fixture.dto.eventId, 'photo.ai', expect.objectContaining({ imageId: String(fixture.enhanced._id) }),
    );
  });

  it('keeps originals only when the event enhancement switch is off', async () => {
    const fixture = makeService(false);
    const result = await fixture.service.create(
      { ...fixture.dto, isEnhanced: false },
      String(fixture.userId),
    );
    expect(result).toMatchObject({ data: fixture.original });
    expect(fixture.model.create).toHaveBeenCalledTimes(1);
    expect(fixture.enhance).not.toHaveBeenCalled();
  });

  it('does not start another enhancement when confirmation is retried', async () => {
    const fixture = makeService();
    const first = fixture.service.create(fixture.dto, String(fixture.userId));
    fixture.finishEnhancement(null);
    await first;
    fixture.model.findOne.mockReturnValue({ exec: jest.fn().mockResolvedValue(fixture.original) });
    const repeated = await fixture.service.create(fixture.dto, String(fixture.userId));
    expect(repeated.idempotent).toBe(true);
    expect(fixture.enhance).toHaveBeenCalledTimes(1);
    expect(fixture.model.create).toHaveBeenCalledTimes(1);
  });

  it('confirms single uploads without a transfer ID while AI is blocked', async () => {
    const fixture = makeService();
    const { clientTransferId, ...dto } = fixture.dto;
    const response = fixture.service.create(dto, String(fixture.userId));
    try {
      const result = await Promise.race([response, new Promise(resolve => setTimeout(() => resolve('blocked'), 50))]);
      expect(result).toMatchObject({ data: fixture.original, enhancedData: null, enhancementJob: null });
      expect(fixture.enhance).toHaveBeenCalledTimes(1);
    } finally {
      fixture.finishEnhancement(fixture.enhanced);
      await response;
      await new Promise(setImmediate);
    }
    expect(fixture.automate).toHaveBeenCalledWith(fixture.enhanced);
  });

  it('returns original batch receipts immediately and limits concurrent AI jobs', async () => {
    const fixture = makeService();
    const imageUrls = ['https://images.example/a.jpg', 'https://images.example/b.jpg', 'https://images.example/c.jpg', 'https://images.example/clip.mp4'];
    const response = fixture.service.createMany({ eventId: fixture.dto.eventId, imageUrls }, String(fixture.userId));
    try {
      const result = await Promise.race([response, new Promise(resolve => setTimeout(() => resolve('blocked'), 50))]);
      expect(result).toMatchObject({ uploadedCount: 4, enhancedData: [], enhancementJobs: [], data: [
        { imageUrl: imageUrls[0], enhancementStatus: 'pending' },
        { imageUrl: imageUrls[1], enhancementStatus: 'pending' },
        { imageUrl: imageUrls[2], enhancementStatus: 'pending' },
        { imageUrl: imageUrls[3], mediaType: 'video' },
      ] });
      expect(fixture.enhance).toHaveBeenCalledTimes(2);
    } finally {
      fixture.finishEnhancement(null);
      await response;
      await new Promise(setImmediate);
    }
    expect(fixture.enhance).toHaveBeenCalledTimes(3);
  });

  it('does not enqueue any batch AI work when the switch is off', async () => {
    const fixture = makeService(false);
    const result = await fixture.service.createMany({
      eventId: fixture.dto.eventId, imageUrls: ['https://images.example/a.jpg'],
    }, String(fixture.userId));
    expect(result.uploadedCount).toBe(1);
    expect(fixture.enhance).not.toHaveBeenCalled();
  });

  it('queues manual enhancement with automatic AI off and returns before inference', async () => {
    const fixture = makeService(false);
    const id = String(fixture.original._id);
    const receipt = fixture.service.enhanceBatch([id], undefined, String(fixture.userId));
    try {
      const result = await Promise.race([receipt, new Promise(resolve => setTimeout(() => resolve('blocked'), 50))]);
      expect(result).toMatchObject({ queued: 1, skipped: 0, failed: 0 });
      expect(fixture.enhance).toHaveBeenCalledTimes(1);
      expect(fixture.model.updateOne).toHaveBeenCalledWith(
        expect.objectContaining({ enhancementStatus: { $nin: ['pending', 'processing', 'completed'] } }),
        { $set: { enhancementStatus: 'pending', enhancementMessage: '' } },
      );
      fixture.model.updateOne.mockResolvedValueOnce({ modifiedCount: 0 });
      const duplicate = await fixture.service.enhanceBatch([id], undefined, String(fixture.userId));
      expect(duplicate).toMatchObject({ queued: 0, skipped: 1 });
      expect(fixture.enhance).toHaveBeenCalledTimes(1);
    } finally {
      fixture.finishEnhancement(fixture.enhanced);
      await receipt;
      await new Promise(setImmediate);
    }
    expect(fixture.automate).toHaveBeenCalledWith(fixture.enhanced);
  });

  it('skips existing enhanced copies and video files without submitting AI', async () => {
    const fixture = makeService(false);
    fixture.model.exists.mockResolvedValueOnce({ _id: new Types.ObjectId() });
    const id = String(fixture.original._id);
    expect(await fixture.service.enhanceExisting(id, String(fixture.userId))).toMatchObject({ queued: false, skipped: true });
    fixture.model.findById.mockResolvedValueOnce({ ...fixture.original, imageUrl: 'https://images.example/clip.mp4' });
    expect(await fixture.service.enhanceExisting(id, String(fixture.userId))).toMatchObject({ queued: false, skipped: true });
    expect(fixture.enhance).not.toHaveBeenCalled();
    fixture.finishEnhancement(null);
  });

  it('keeps a saved camera photo confirmed even when background enhancement fails', async () => {
    const fixture = makeService();
    const log = jest.spyOn(Logger.prototype, 'error').mockImplementation(() => undefined);
    const response = fixture.service.create(fixture.dto, String(fixture.userId));
    fixture.rejectEnhancement(new Error('AI unavailable'));
    await expect(response).resolves.toMatchObject({ data: fixture.original });
    await new Promise(setImmediate);
    expect(log).toHaveBeenCalledWith('image-enhance-failed', 'AI unavailable');
    expect(fixture.model.updateOne).toHaveBeenCalledWith({ _id: String(fixture.original._id) }, { $set: { enhancementStatus: 'failed', enhancementMessage: expect.any(String) } });
  });
});
