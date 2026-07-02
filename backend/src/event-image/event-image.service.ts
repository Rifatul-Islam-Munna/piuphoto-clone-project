import { HttpException, Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import axios from 'axios';
import { InjectModel } from '@nestjs/mongoose';
import { Model, Types } from 'mongoose';
import {
  CreateEventImageDto,
  CreateEventImagesBatchDto,
  EventImageFilterDto,
  MyPictureDto,
} from './dto/create-event-image.dto';
import { UpdateEventImageDto } from './dto/update-event-image.dto';
import { EventImage, EventImageDocument } from './entities/event-image.entity';
import { Event, EventDocument } from '../event/entities/event.entity';
import { Album, AlbumDocument } from '../album/entities/album.entity';
import {
  EventInvitation,
  EventInvitationDocument,
  EventInvitationStatus,
} from '../event/entities/event-invitation.entity';
import { User, UserDocument, UserType } from '../user/entities/user.entity';
import {
  SubscriptionPlan,
  SubscriptionPlanDocument,
} from '../subscription/entities/subscription-plan.entity';
import { FaceVectorService } from '../face-search/face-vector.service';
import { QdrantFaceService } from '../face-search/qdrant-face.service';
import { createHash, createPublicKey, verify } from 'crypto';
import type { IncomingHttpHeaders } from 'http';
import { FalWebhookDto } from './dto/fal-webhook.dto';
import {
  FalEnhancementJob,
  FalEnhancementJobDocument,
  FalEnhancementJobStatus,
} from './entities/fal-enhancement-job.entity';

@Injectable()
export class EventImageService {
  private readonly logger = new Logger(EventImageService.name);
  private activeFaceJobs = 0;
  private readonly faceJobQueue: EventImageDocument[] = [];
  private falJwksCache: { keys: Array<{ x?: string }>; fetchedAt: number } | null =
    null;

  constructor(
    @InjectModel(EventImage.name)
    private eventImageModel: Model<EventImageDocument>,
    @InjectModel(Event.name)
    private eventModel: Model<EventDocument>,
    @InjectModel(Album.name)
    private albumModel: Model<AlbumDocument>,
    @InjectModel(EventInvitation.name)
    private eventInvitationModel: Model<EventInvitationDocument>,
    @InjectModel(User.name)
    private userModel: Model<UserDocument>,
    @InjectModel(SubscriptionPlan.name)
    private subscriptionPlanModel: Model<SubscriptionPlanDocument>,
    @InjectModel(FalEnhancementJob.name)
    private falEnhancementJobModel: Model<FalEnhancementJobDocument>,
    private readonly configService: ConfigService,
    private readonly faceVectorService: FaceVectorService,
    private readonly qdrantFaceService: QdrantFaceService,
  ) {}

  private toObjectId(id: string) {
    return new Types.ObjectId(id);
  }

  private async assertCanUseEvent(
    eventId: string,
    userId?: string,
    role?: string,
  ) {
    if (!Types.ObjectId.isValid(eventId)) {
      throw new HttpException('Invalid event id', 400);
    }

    const event = await this.eventModel
      .findById(eventId)
      .select('userId title autoEnhanceImages')
      .lean();

    if (!event) {
      throw new HttpException('Event not found', 400);
    }

    if (!userId || !Types.ObjectId.isValid(userId)) {
      throw new HttpException('Invalid user id', 400);
    }

    if (role === UserType.ADMIN || String(event.userId) === userId) {
      return event;
    }

    const invitation = await this.eventInvitationModel
      .findOne({
        eventId: this.toObjectId(eventId),
        photographerId: this.toObjectId(userId),
        status: EventInvitationStatus.ACCEPTED,
      })
      .select('_id')
      .lean();

    if (!invitation) {
      throw new HttpException(
        'Only the owner or an accepted photographer can upload to this event',
        403,
      );
    }

    return event;
  }

  private defaultEnhancePrompt() {
    return [
      'Subtle professional event photo enhancement.',
      'Preserve the original image as much as possible.',
      'Keep the same person identity, facial structure, skin texture, body shape, age, pose, clothing, hairstyle, background, scene, perspective, crop, composition, lighting direction, and event context.',
      'Only make gentle corrections to color, white balance, exposure, contrast, dynamic range, noise, sharpness, and clarity.',
      'Retain natural pores, realistic skin texture, original proportions, and authentic camera look.',
      'Do not over-smooth skin, over-sharpen faces, reshape the body, enlarge eyes, alter facial features, remove important details, or create plastic AI skin.',
      'Do not add new people, objects, text, logos, watermarks, accessories, makeup, jewelry, background elements, or change outfit colors.',
      'If any beautification is requested, apply it very lightly and naturally.',
      'Output should look like the same original photo, only gently polished by a professional editor.',
    ].join(' ');
  }

  private enhanceModePrompt(prompt?: string) {
    const value = prompt?.trim();
    if (!value) return '';

    const normalized = value.toLowerCase();
    const presets: Array<{ match: string[]; text: string }> = [
      {
        match: ['colour enhancement', 'color enhancement'],
        text: [
          'Apply only subtle color enhancement.',
          'Improve white balance, skin tone accuracy, and tonal richness softly.',
          'Keep original colors realistic and faithful to the scene.',
        ].join(' '),
      },
      {
        match: ['skin beautification'],
        text: [
          'Apply very light skin cleanup only.',
          'Reduce temporary blemishes and uneven tone gently while preserving pores, wrinkles, fine texture, and natural detail.',
          'Do not create smooth plastic skin.',
        ].join(' '),
      },
      {
        match: ['facial beautification'],
        text: [
          'Apply very subtle facial beautification only.',
          'Keep the same face shape, eyes, nose, lips, jawline, expression, and identity.',
          'Only reduce minor distraction softly without changing facial structure.',
        ].join(' '),
      },
      {
        match: ['body beautification'],
        text: [
          'Apply very subtle body refinement only if clearly needed.',
          'Do not change body shape, weight, proportions, pose, or clothing fit in any noticeable way.',
          'Preserve the real appearance of the subject.',
        ].join(' '),
      },
      {
        match: ['vehicle privacy protection'],
        text: [
          'Protect visible vehicle privacy details only.',
          'Blur or obscure license plates and sensitive identifiers gently while keeping the rest of the image unchanged.',
        ].join(' '),
      },
    ];

    for (const preset of presets) {
      if (preset.match.some((keyword) => normalized.includes(keyword))) {
        return preset.text;
      }
    }

    return [
      'User requested these extra enhancement notes.',
      'Follow them only in a subtle, realistic, preserve-original way:',
      value,
    ].join(' ');
  }

  private buildEnhancePrompt(prompt?: string) {
    const base = this.defaultEnhancePrompt();
    const modePrompt = this.enhanceModePrompt(prompt);
    return modePrompt ? `${base} ${modePrompt}` : base;
  }

  private async enhanceImage(imageUrl: string, prompt?: string) {
    const falKey =
      this.configService.get<string>('FAL_KEY') ||
      this.configService.get<string>('FAL_API_KEY');

    if (!falKey) {
      throw new HttpException('FAL key is not configured', 500);
    }

    const response = await axios.post<{
      images?: { url?: string }[];
    }>(
      'https://fal.run/fal-ai/bytedance/seedream/v4/edit',
      {
        prompt: this.buildEnhancePrompt(prompt),
        image_urls: [imageUrl],
        image_size: 'auto_4K',
        num_images: 1,
        max_images: 1,
        enable_safety_checker: true,
        enhance_prompt_mode: 'standard',
      },
      {
        headers: {
          Authorization: `Key ${falKey}`,
          'Content-Type': 'application/json',
        },
        timeout: 120000,
      },
    );

    const enhancedUrl = response.data.images?.[0]?.url;
    if (!enhancedUrl) {
      throw new HttpException('FAL returned no enhanced image', 500);
    }

    return enhancedUrl;
  }

  private useFalWebhook() {
    return this.configService.get<string>('IS_WEBHOOK')?.toLowerCase() === 'true';
  }

  private falWebhookUrl() {
    const configuredUrl = this.configService.get<string>('FAL_WEBHOOK_URL');
    if (!configuredUrl) {
      throw new HttpException('FAL webhook URL is not configured', 500);
    }

    let webhookUrl: URL;
    try {
      webhookUrl = new URL(configuredUrl);
    } catch {
      throw new HttpException('FAL webhook URL is invalid', 500);
    }

    webhookUrl.searchParams.set('type', 'puiphoto');
    return webhookUrl.toString();
  }

  async verifyFalWebhookSignature(
    headers: IncomingHttpHeaders,
    rawBody?: Buffer,
  ) {
    const requestId = headers['x-fal-webhook-request-id'];
    const userId = headers['x-fal-webhook-user-id'];
    const timestamp = headers['x-fal-webhook-timestamp'];
    const signature = headers['x-fal-webhook-signature'];

    if (
      typeof requestId !== 'string' ||
      typeof userId !== 'string' ||
      typeof timestamp !== 'string' ||
      typeof signature !== 'string' ||
      !rawBody
    ) {
      throw new HttpException('Invalid FAL webhook signature headers', 401);
    }

    const timestampNumber = Number(timestamp);
    if (
      !Number.isFinite(timestampNumber) ||
      Math.abs(Math.floor(Date.now() / 1000) - timestampNumber) > 300
    ) {
      throw new HttpException('Expired FAL webhook signature', 401);
    }

    const now = Date.now();
    if (!this.falJwksCache || now - this.falJwksCache.fetchedAt > 86_400_000) {
      const response = await axios.get<{ keys?: Array<{ x?: string }> }>(
        'https://rest.fal.ai/.well-known/jwks.json',
        { timeout: 10000 },
      );
      this.falJwksCache = {
        keys: response.data.keys || [],
        fetchedAt: now,
      };
    }

    const bodyHash = createHash('sha256').update(rawBody).digest('hex');
    const message = Buffer.from(
      [requestId, userId, timestamp, bodyHash].join('\n'),
      'utf8',
    );
    const signatureBytes = Buffer.from(signature, 'hex');
    const ed25519SpkiPrefix = Buffer.from('302a300506032b6570032100', 'hex');
    const valid = this.falJwksCache.keys.some((key) => {
      if (!key.x) return false;
      try {
        const publicKey = createPublicKey({
          key: Buffer.concat([
            ed25519SpkiPrefix,
            Buffer.from(key.x, 'base64url'),
          ]),
          format: 'der',
          type: 'spki',
        });
        return verify(null, message, publicKey, signatureBytes);
      } catch {
        return false;
      }
    });

    if (!valid) {
      throw new HttpException('Invalid FAL webhook signature', 401);
    }
  }

  private async submitEnhancementWebhook(
    imageUrl: string,
    prompt: string | undefined,
    context: {
      eventId: string;
      uploaderId: string;
      ownerId: string;
      albumId?: string;
    },
  ) {
    const falKey =
      this.configService.get<string>('FAL_KEY') ||
      this.configService.get<string>('FAL_API_KEY');

    if (!falKey) {
      throw new HttpException('FAL key is not configured', 500);
    }

    const endpoint = new URL(
      'https://queue.fal.run/fal-ai/bytedance/seedream/v4/edit',
    );
    endpoint.searchParams.set('fal_webhook', this.falWebhookUrl());

    const response = await axios.post<{ request_id?: string }>(
      endpoint.toString(),
      {
        prompt: this.buildEnhancePrompt(prompt),
        image_urls: [imageUrl],
        image_size: 'auto_4K',
        num_images: 1,
        max_images: 1,
        enable_safety_checker: true,
        enhance_prompt_mode: 'standard',
      },
      {
        headers: {
          Authorization: `Key ${falKey}`,
          'Content-Type': 'application/json',
        },
        timeout: 30000,
      },
    );

    const requestId = response.data.request_id;
    if (!requestId) {
      throw new HttpException('FAL returned no request id', 502);
    }

    await this.falEnhancementJobModel.create({
      requestId,
      type: 'puiphoto',
      eventId: this.toObjectId(context.eventId),
      uploaderId: this.toObjectId(context.uploaderId),
      ownerId: this.toObjectId(context.ownerId),
      albumId: context.albumId ? this.toObjectId(context.albumId) : undefined,
      sourceImageUrl: imageUrl,
      creditsCharged: 3,
      status: FalEnhancementJobStatus.PENDING,
    });

    return { requestId, status: FalEnhancementJobStatus.PENDING };
  }

  private extractPermissionLimit(
    permissions: Record<string, unknown>[] = [],
    key: string,
  ) {
    for (const permission of permissions) {
      if (
        permission?.key === key &&
        permission.value !== undefined &&
        permission.value !== null
      ) {
        const numericValue = Number(permission.value);
        if (!Number.isNaN(numericValue)) return numericValue;
      }

      if (
        Object.prototype.hasOwnProperty.call(permission, key) &&
        permission[key] !== undefined &&
        permission[key] !== null
      ) {
        const numericValue = Number(permission[key]);
        if (!Number.isNaN(numericValue)) return numericValue;
      }
    }

    return 0;
  }

  private async getOwnerPlanMeta(ownerId: string) {
    const user = await this.userModel
      .findById(ownerId)
      .select('credits subscriptionPlanId')
      .lean();

    const plan = user?.subscriptionPlanId
      ? await this.subscriptionPlanModel
          .findById(user.subscriptionPlanId)
          .select('permissions features')
          .lean()
      : null;

    const permissions = Array.isArray(plan?.permissions)
      ? (plan.permissions as unknown as Record<string, unknown>[])
      : [];

    return {
      credits: user?.credits || 0,
      monthlyPhotoLimit: this.extractPermissionLimit(
        permissions,
        'photos.monthly',
      ),
      hasCustomEnhancer: Array.isArray(plan?.features)
        ? plan.features.includes('custom.enhancer')
        : false,
    };
  }

  private async assertEventUploadLimit(
    eventId: string,
    ownerId: string,
    uploadCount = 1,
  ) {
    const meta = await this.getOwnerPlanMeta(ownerId);
    if (meta.monthlyPhotoLimit <= 0) return;

    const currentCount = await this.eventImageModel.countDocuments({
      eventId: this.toObjectId(eventId),
      isEnhanced: { $ne: true },
    });

    if (currentCount + uploadCount > meta.monthlyPhotoLimit) {
      throw new HttpException('Max image upload limit reached for this event', 400);
    }
  }

  private async tryEnhanceForOwner(
    imageUrl: string,
    eventId: string,
    uploaderId: string,
    ownerId: string,
    albumId?: string,
    prompt?: string,
  ): Promise<EventImageDocument | { requestId: string; status: string } | null> {
    const meta = await this.getOwnerPlanMeta(ownerId);
    const customPrompt = prompt?.trim();
    const finalPrompt = meta.hasCustomEnhancer ? customPrompt : undefined;

    if (meta.credits < 3) return null;

    const chargedUser = await this.userModel
      .findOneAndUpdate(
        { _id: this.toObjectId(ownerId), credits: { $gte: 3 } },
        { $inc: { credits: -3 } },
        { new: true },
      )
      .select('_id')
      .lean();

    if (!chargedUser) return null;

    try {
      if (this.useFalWebhook()) {
        return await this.submitEnhancementWebhook(imageUrl, finalPrompt, {
          eventId,
          uploaderId,
          ownerId,
          albumId,
        });
      }

      const enhancedUrl = await this.enhanceImage(imageUrl, finalPrompt);
      return await this.eventImageModel.create({
        eventId: this.toObjectId(eventId),
        imageUrl: enhancedUrl,
        userTakenBy: this.toObjectId(uploaderId),
        albumId: albumId ? this.toObjectId(albumId) : undefined,
        isEnhanced: true,
      });
    } catch (error) {
      await this.userModel.findByIdAndUpdate(ownerId, { $inc: { credits: 3 } });
      throw error;
    }
  }

  private isEnhancementJobResult(
    value: EventImageDocument | { requestId: string; status: string },
  ): value is { requestId: string; status: string } {
    return (
      !('_id' in value) &&
      typeof (value as { requestId?: unknown }).requestId === 'string'
    );
  }

  async handleFalWebhook(type: string, webhook: FalWebhookDto) {
    if (type !== 'puiphoto') {
      this.logger.log(
        `fal-webhook-ignored type=${type} requestId=${webhook.request_id}`,
      );
      return { received: true, ignored: true };
    }

    const job = await this.falEnhancementJobModel
      .findOne({ requestId: webhook.request_id, type: 'puiphoto' })
      .exec();

    if (!job) {
      this.logger.warn(`fal-webhook-job-not-found requestId=${webhook.request_id}`);
      return { received: true, ignored: true };
    }

    if (job.status === FalEnhancementJobStatus.COMPLETED) {
      return { received: true, duplicate: true };
    }

    if (webhook.status === 'ERROR') {
      const failedJob = await this.falEnhancementJobModel.findOneAndUpdate(
        {
          _id: job._id,
          status: FalEnhancementJobStatus.PENDING,
        },
        {
          $set: {
            status: FalEnhancementJobStatus.FAILED,
            error: webhook.error || webhook.payload_error || 'FAL request failed',
          },
        },
        { new: true },
      );

      if (failedJob) {
        await this.userModel.findByIdAndUpdate(job.ownerId, {
          $inc: { credits: job.creditsCharged },
        });
      }

      return { received: true, failed: true };
    }

    const enhancedUrl = webhook.payload?.images?.[0]?.url;
    if (!enhancedUrl) {
      throw new HttpException('FAL webhook returned no enhanced image', 400);
    }
    try {
      const imageUrl = new URL(enhancedUrl);
      if (!['http:', 'https:'].includes(imageUrl.protocol)) throw new Error();
    } catch {
      throw new HttpException('FAL webhook returned an invalid image URL', 400);
    }

    let eventImage = await this.eventImageModel.findOne({
      falRequestId: webhook.request_id,
    });

    if (!eventImage) {
      eventImage = await this.eventImageModel.create({
        eventId: job.eventId,
        imageUrl: enhancedUrl,
        userTakenBy: job.uploaderId,
        albumId: job.albumId,
        isEnhanced: true,
        falRequestId: webhook.request_id,
      });
      this.queueFaceIndex(eventImage);
    }

    await this.falEnhancementJobModel.updateOne(
      { _id: job._id },
      { $set: { status: FalEnhancementJobStatus.COMPLETED }, $unset: { error: '' } },
    );

    return { received: true, saved: true, eventImageId: String(eventImage._id) };
  }

  private async assertAlbumBelongsToEvent(albumId: string, eventId: string) {
    if (!Types.ObjectId.isValid(albumId)) {
      throw new HttpException('Invalid album id', 400);
    }

    const album = await this.albumModel
      .findById(albumId)
      .select('eventId')
      .lean();

    if (!album) {
      throw new HttpException('Album not found', 400);
    }

    if (String(album.eventId) !== eventId) {
      throw new HttpException('Album does not belong to this event', 400);
    }
  }

  private queueFaceIndex(eventImage: EventImageDocument) {
    this.faceJobQueue.push(eventImage);
    this.drainFaceJobQueue();
  }

  private faceIndexConcurrency() {
    return Math.max(
      Number(this.configService.get<string>('FACE_INDEX_CONCURRENCY')) || 1,
      1,
    );
  }

  private drainFaceJobQueue() {
    while (
      this.activeFaceJobs < this.faceIndexConcurrency() &&
      this.faceJobQueue.length
    ) {
      const eventImage = this.faceJobQueue.shift();
      if (!eventImage) return;

      this.activeFaceJobs += 1;
      void this.indexEventImageFaces(eventImage)
        .catch((error) => {
          this.logger.error('face-index-failed', error);
        })
        .finally(() => {
          this.activeFaceJobs -= 1;
          this.drainFaceJobQueue();
        });
    }
  }

  private async indexEventImageFaces(eventImage: EventImageDocument) {
    const vectors = await this.faceVectorService.vectorsFromUrl(eventImage.imageUrl);

    await this.qdrantFaceService.upsertFaces(vectors, {
      eventId: String(eventImage.eventId),
      eventImageId: String(eventImage._id),
      imageUrl: eventImage.imageUrl,
      isEnhanced: Boolean(eventImage.isEnhanced),
      albumId: eventImage.albumId ? String(eventImage.albumId) : undefined,
    });

    this.logger.log(`face-indexed image=${eventImage._id} faces=${vectors.length}`);
  }

  async create(
    createEventImageDto: CreateEventImageDto,
    userId?: string,
    role?: string,
  ) {
    const event = await this.assertCanUseEvent(
      createEventImageDto.eventId,
      userId,
      role,
    );

    if (createEventImageDto.albumId) {
      await this.assertAlbumBelongsToEvent(
        createEventImageDto.albumId,
        createEventImageDto.eventId,
      );
    }

    await this.assertEventUploadLimit(
      createEventImageDto.eventId,
      String(event.userId),
    );

    const eventImage = await this.eventImageModel.create({
      eventId: this.toObjectId(createEventImageDto.eventId),
      imageUrl: createEventImageDto.imageUrl,
      userTakenBy: this.toObjectId(String(userId)),
      albumId: createEventImageDto.albumId
        ? this.toObjectId(createEventImageDto.albumId)
        : undefined,
      isEnhanced: createEventImageDto.isEnhanced ?? false,
    });
    this.queueFaceIndex(eventImage);

    let enhancedImage: EventImageDocument | null = null;
    let enhancementJob: { requestId: string; status: string } | null = null;
    if (event.autoEnhanceImages && !createEventImageDto.isEnhanced) {
      try {
        const enhancement = await this.tryEnhanceForOwner(
          createEventImageDto.imageUrl,
          createEventImageDto.eventId,
          String(userId),
          String(event.userId),
          createEventImageDto.albumId,
          createEventImageDto.enhancePrompt,
        );
        if (enhancement && this.isEnhancementJobResult(enhancement)) {
          enhancementJob = enhancement;
        } else if (enhancement) {
          enhancedImage = enhancement as EventImageDocument;
          this.queueFaceIndex(enhancedImage);
        }
      } catch (error) {
        this.logger.error('image-enhance-failed', error);
      }
    }

    return {
      message: 'Event image created successfully',
      data: eventImage,
      enhancedData: enhancedImage,
      enhancementJob,
    };
  }

  async createMany(
    createEventImagesBatchDto: CreateEventImagesBatchDto,
    userId?: string,
    role?: string,
  ) {
    const event = await this.assertCanUseEvent(
      createEventImagesBatchDto.eventId,
      userId,
      role,
    );

    if (createEventImagesBatchDto.albumId) {
      await this.assertAlbumBelongsToEvent(
        createEventImagesBatchDto.albumId,
        createEventImagesBatchDto.eventId,
      );
    }

    await this.assertEventUploadLimit(
      createEventImagesBatchDto.eventId,
      String(event.userId),
      createEventImagesBatchDto.imageUrls.length,
    );

    const docs = createEventImagesBatchDto.imageUrls.map((imageUrl) => ({
      eventId: this.toObjectId(createEventImagesBatchDto.eventId),
      imageUrl,
      userTakenBy: this.toObjectId(String(userId)),
      albumId: createEventImagesBatchDto.albumId
        ? this.toObjectId(createEventImagesBatchDto.albumId)
        : undefined,
      isEnhanced: createEventImagesBatchDto.isEnhanced ?? false,
    }));

    const eventImages = await this.eventImageModel.insertMany(docs);
    eventImages.forEach((eventImage) => this.queueFaceIndex(eventImage));

    let enhancedImages: EventImageDocument[] = [];
    let enhancementJobs: Array<{ requestId: string; status: string }> = [];
    if (event.autoEnhanceImages && !createEventImagesBatchDto.isEnhanced) {
      const results = await Promise.allSettled(
        createEventImagesBatchDto.imageUrls.map((imageUrl) =>
          this.tryEnhanceForOwner(
            imageUrl,
            createEventImagesBatchDto.eventId,
            String(userId),
            String(event.userId),
            createEventImagesBatchDto.albumId,
            createEventImagesBatchDto.enhancePrompt,
          ),
        ),
      );

      const enhancements = results
        .map((result) => {
          if (result.status === 'rejected') {
            this.logger.error('image-enhance-failed', result.reason);
            return null;
          }
          return result.value;
        })
        .filter((image): image is NonNullable<typeof image> => image !== null);

      enhancementJobs = enhancements.filter(
        (enhancement): enhancement is { requestId: string; status: string } =>
          this.isEnhancementJobResult(enhancement),
      );
      enhancedImages = enhancements.filter(
        (enhancement): enhancement is EventImageDocument =>
          !this.isEnhancementJobResult(enhancement),
      );

      enhancedImages.forEach((eventImage) => this.queueFaceIndex(eventImage));
    }

    return {
      message: 'Event images created successfully',
      data: eventImages,
      enhancedData: enhancedImages,
      enhancementJobs,
      uploadedCount: eventImages.length,
    };
  }

  async findMyPictures(
    file: Express.Multer.File,
    query: MyPictureDto,
    userId?: string,
    role?: string,
    publicAccess = false,
  ) {
    if (!file?.buffer) {
      throw new HttpException('Face image file is required', 400);
    }

    if (publicAccess) {
      if (!query.eventId || !Types.ObjectId.isValid(query.eventId)) {
        throw new HttpException('Invalid event id', 400);
      }

      const event = await this.eventModel
        .findOne({
          _id: this.toObjectId(query.eventId),
          isActive: true,
          isPublished: true,
        })
        .select('_id')
        .lean();

      if (!event) {
        throw new HttpException('Event not found', 404);
      }
    } else if (query.eventId) {
      await this.assertCanUseEvent(query.eventId, userId, role);
    }

    const { faces, vectors } = await this.faceVectorService.detectAndVectorFromBuffer(
      file.buffer,
      file.originalname || 'image.jpg',
      file.mimetype || 'image/jpeg',
    );
    if (!faces.length) {
      throw new HttpException('No usable face found in uploaded image', 400);
    }
    if (!vectors.length) {
      return {
        data: [],
        totalItems: 0,
        faces,
        message:
          'Face boxes detected, but matching needs vector, embedding, or descriptor data',
      };
    }

    const limit = Math.min(
      Math.max(Number(query.limit) || 10000, 1),
      10000,
    );
    const scoreThreshold = Number(query.scoreThreshold) || 0.45;
    const results = (
      await Promise.all(
        vectors.map((vector) =>
          this.qdrantFaceService.search(
            vector,
            query.eventId,
            limit,
            scoreThreshold,
          ),
        ),
      )
    ).flat();

    const byImageId = new Map<string, { score: number; faceCount: number }>();
    for (const result of results) {
      const imageIds = [
        ...(result.payload?.eventImageIds || []),
        result.payload?.eventImageId,
      ].filter((imageId): imageId is string => Boolean(imageId));

      for (const imageId of imageIds) {
        if (!Types.ObjectId.isValid(imageId)) continue;

        const existing = byImageId.get(imageId);
        byImageId.set(imageId, {
          score: Math.max(existing?.score || 0, result.score),
          faceCount: (existing?.faceCount || 0) + 1,
        });
      }
    }

    const ids = [...byImageId.keys()]
      .sort((a, b) => (byImageId.get(b)?.score || 0) - (byImageId.get(a)?.score || 0))
      .slice(0, limit);

    const data = await this.eventImageModel
      .find({
        _id: { $in: ids.map((id) => this.toObjectId(id)) },
        ...(query.eventId ? { eventId: this.toObjectId(query.eventId) } : {}),
      })
      .populate('eventId', 'title description image')
      .populate('albumId', 'title description')
      .populate('userTakenBy', 'name email phone userId role')
      .lean()
      .exec();

    const dataById = new Map(data.map((image) => [String(image._id), image]));
    const sortedData = ids
      .map((id) => {
        const image = dataById.get(id);
        if (!image) return null;

        return {
          ...image,
          faceMatch: byImageId.get(id),
        };
      })
      .filter(Boolean);

    return {
      data: sortedData,
      totalItems: sortedData.length,
      faces,
    };
  }

  async findAll(query: EventImageFilterDto) {
    const page = Math.max(Number(query.page) || 1, 1);
    const limit = Math.min(Math.max(Number(query.limit) || 20, 1), 100);
    const skip = (page - 1) * limit;
    const filter: Record<string, unknown> = {};

    if (query.eventId && Types.ObjectId.isValid(query.eventId)) {
      filter.eventId = this.toObjectId(query.eventId);
    }

    if (query.userTakenBy && Types.ObjectId.isValid(query.userTakenBy)) {
      filter.userTakenBy = this.toObjectId(query.userTakenBy);
    }

    if (query.albumId && Types.ObjectId.isValid(query.albumId)) {
      filter.albumId = this.toObjectId(query.albumId);
    }

    if (query.isEnhanced !== undefined && query.isEnhanced !== 'all') {
      filter.isEnhanced = query.isEnhanced === 'true';
    }

    const [data, totalItems] = await Promise.all([
      this.eventImageModel
        .find(filter)
        .populate('eventId', 'title description image')
        .populate('albumId', 'title description')
        .populate('userTakenBy', 'name email phone userId role')
        .sort({ createdAt: -1 })
        .skip(skip)
        .limit(limit)
        .lean()
        .exec(),
      this.eventImageModel.countDocuments(filter).exec(),
    ]);

    const totalPages = Math.ceil(totalItems / limit);

    return {
      data,
      page,
      limit,
      totalItems,
      totalPages,
      hasNextPage: page < totalPages,
      hasPreviousPage: page > 1,
    };
  }

  async findPublicByEvent(eventId: string, albumId?: string) {
    if (!eventId || !Types.ObjectId.isValid(eventId)) {
      throw new HttpException('Invalid event id', 400);
    }

    const event = await this.eventModel
      .findOne({
        _id: this.toObjectId(eventId),
        isActive: true,
        isPublished: true,
      })
      .select('_id')
      .lean();

    if (!event) {
      throw new HttpException('Event not found', 404);
    }

    if (albumId) {
      await this.assertAlbumBelongsToEvent(albumId, eventId);
    }

    const data = await this.eventImageModel
      .find({
        eventId: this.toObjectId(eventId),
        ...(albumId ? { albumId: this.toObjectId(albumId) } : {}),
      })
      .populate('eventId', 'title description image')
      .populate('albumId', 'title description')
      .populate('userTakenBy', 'name email phone userId role')
      .sort({ createdAt: -1 })
      .lean()
      .exec();

    return { data, totalItems: data.length };
  }

  async findOne(id: string) {
    if (!Types.ObjectId.isValid(id)) {
      throw new HttpException('Invalid event image id', 400);
    }

    const eventImage = await this.eventImageModel
      .findById(id)
      .populate('eventId', 'title description image')
      .populate('albumId', 'title description')
      .populate('userTakenBy', 'name email phone userId role')
      .lean();

    if (!eventImage) {
      throw new HttpException('Event image not found', 400);
    }

    return eventImage;
  }

  async update(
    id: string,
    updateEventImageDto: UpdateEventImageDto,
    userId?: string,
    role?: string,
  ) {
    if (!Types.ObjectId.isValid(id)) {
      throw new HttpException('Invalid event image id', 400);
    }

    const existing = await this.eventImageModel
      .findById(id)
      .select('eventId')
      .lean();

    if (!existing) {
      throw new HttpException('Event image not found', 400);
    }

    const eventId = updateEventImageDto.eventId ?? String(existing.eventId);
    await this.assertCanUseEvent(eventId, userId, role);

    if (updateEventImageDto.albumId) {
      await this.assertAlbumBelongsToEvent(updateEventImageDto.albumId, eventId);
    }

    const update: Record<string, unknown> = { ...updateEventImageDto };
    if (updateEventImageDto.eventId) {
      update.eventId = this.toObjectId(updateEventImageDto.eventId);
    }
    if (updateEventImageDto.albumId) {
      update.albumId = this.toObjectId(updateEventImageDto.albumId);
    }
    const eventImage = await this.eventImageModel
      .findByIdAndUpdate(id, { $set: update }, { new: true })
      .lean();

    return { message: 'Event image updated successfully', data: eventImage };
  }

  async remove(id: string, userId?: string, role?: string) {
    if (!Types.ObjectId.isValid(id)) {
      throw new HttpException('Invalid event image id', 400);
    }

    const existing = await this.eventImageModel
      .findById(id)
      .select('eventId')
      .lean();

    if (!existing) {
      throw new HttpException('Event image not found', 400);
    }

    await this.assertCanUseEvent(String(existing.eventId), userId, role);
    const eventImage = await this.eventImageModel.findByIdAndDelete(id).lean();

    return { message: 'Event image deleted successfully', data: eventImage };
  }

  async enhanceExisting(
    id: string,
    userId?: string,
    role?: string,
    prompt?: string,
  ) {
    if (!Types.ObjectId.isValid(id)) {
      throw new HttpException('Invalid event image id', 400);
    }

    const existing = await this.eventImageModel
      .findById(id)
      .select('eventId imageUrl albumId isEnhanced')
      .lean();

    if (!existing) {
      throw new HttpException('Event image not found', 400);
    }

    const event = await this.assertCanUseEvent(
      String(existing.eventId),
      userId,
      role,
    );

    const enhancedImage = await this.tryEnhanceForOwner(
      existing.imageUrl,
      String(existing.eventId),
      String(userId),
      String(event.userId),
      existing.albumId ? String(existing.albumId) : undefined,
      prompt,
    );

    if (!enhancedImage) {
      return {
        message: 'Enhance skipped because owner has not enough credits',
        data: null,
        skipped: true,
      };
    }

    return {
      message: 'Image enhanced successfully',
      data: enhancedImage,
      skipped: false,
    };
  }
}
