import {
  HttpException,
  Injectable,
  Logger,
  MessageEvent,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import axios from 'axios';
import sharp from 'sharp';
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
import { EventMemberService } from '../event-member/event-member.service';
import { TransferStatusService } from '../transfer-status/transfer-status.service';
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
import { Observable, Subject, interval, map, merge } from 'rxjs';
import { FalWebhookDto } from './dto/fal-webhook.dto';
import {
  FalEnhancementJob,
  FalEnhancementJobDocument,
  FalEnhancementJobStatus,
} from './entities/fal-enhancement-job.entity';
import { GalleryAccessService } from '../gallery-access/gallery-access.service';
import { GuestGalleryService } from '../guest-gallery/guest-gallery.service';
import { MediaAiService } from './media-ai.service';
import { RetouchWorkflowService } from '../retouch-workflow/retouch-workflow.service';
import { WorkflowWebhookPublisherService } from '../external-api/workflow-webhook-publisher.service';

@Injectable()
export class EventImageService {
  private readonly logger = new Logger(EventImageService.name);
  private readonly galleryStreams = new Map<
    string,
    Subject<Record<string, unknown>>
  >();
  private activeFaceJobs = 0;
  private readonly faceJobQueue: EventImageDocument[] = [];
  private falJwksCache: {
    keys: Array<{ x?: string }>;
    fetchedAt: number;
  } | null = null;

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
    private readonly eventMemberService: EventMemberService,
    private readonly transferStatusService: TransferStatusService,
    private readonly galleryAccessService: GalleryAccessService,
    private readonly guestGalleryService: GuestGalleryService,
    private readonly mediaAiService: MediaAiService,
    private readonly retouchWorkflowService: RetouchWorkflowService,
    private readonly workflowWebhooks: WorkflowWebhookPublisherService,
  ) {}

  private gallerySubject(eventId: string) {
    let subject = this.galleryStreams.get(eventId);
    if (!subject) {
      subject = new Subject<Record<string, unknown>>();
      this.galleryStreams.set(eventId, subject);
    }
    return subject;
  }

  private emitGallery(eventId: string, payload: Record<string, unknown>) {
    this.gallerySubject(eventId).next({
      ...payload,
      eventId,
      at: new Date().toISOString(),
    });
  }

  async streamPublic(
    eventId: string,
    albumId?: string,
    accessToken?: string,
  ): Promise<Observable<MessageEvent>> {
    await this.galleryAccessService.assertCanView(
      eventId,
      albumId,
      accessToken,
    );
    const updates = this.gallerySubject(eventId)
      .asObservable()
      .pipe(
        map((payload) => ({ type: 'gallery', data: payload }) as MessageEvent),
      );
    const heartbeat = interval(15000).pipe(
      map(
        () =>
          ({
            type: 'heartbeat',
            data: { at: new Date().toISOString() },
          }) as MessageEvent,
      ),
    );
    return merge(updates, heartbeat);
  }

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
      .select('userId title autoEnhanceImages autoPublishImages requireReview publishPolicy')
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

    await this.eventMemberService.assertCanAccess(eventId, userId, role);
    return event;
  }

  private async resolvePublishPolicy(
    event: { publishPolicy?: string; autoPublishImages?: boolean; requireReview?: boolean },
    albumId?: string,
  ) {
    let policy = event.publishPolicy ||
      (event.requireReview || event.autoPublishImages === false ? 'manual' : 'auto_upload');
    if (albumId && Types.ObjectId.isValid(albumId)) {
      const album = await this.albumModel.findById(albumId).select('publishPolicy').lean();
      if (album?.publishPolicy && album.publishPolicy !== 'inherit') policy = album.publishPolicy;
    }
    return policy as 'auto_upload' | 'auto_ai' | 'manual';
  }

  private queuePhotoAutomation(eventImage: EventImageDocument) {
    if (eventImage.mediaType === 'video') return;
    this.queueFaceIndex(eventImage);
    this.mediaAiService.queueAnalysis(eventImage);
    void this.retouchWorkflowService.registerIncoming(eventImage).catch((error) =>
      this.logger.warn(`retouch-register-failed ${String(error)}`),
    );
  }

  private inferMediaType(url: string, supplied?: 'photo' | 'video') {
    if (supplied) return supplied;
    const clean = url.toLowerCase().split('?')[0];
    return ['.mp4', '.mov', '.m4v', '.webm', '.ogg', '.mkv'].some((ext) => clean.endsWith(ext)) ? 'video' : 'photo';
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
    return (
      this.configService.get<string>('IS_WEBHOOK')?.toLowerCase() === 'true'
    );
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
      sourceEventImageId?: string;
      isPublished: boolean;
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
      sourceEventImageId: context.sourceEventImageId
        ? this.toObjectId(context.sourceEventImageId)
        : undefined,
      isPublished: context.isPublished,
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
      throw new HttpException(
        'Max image upload limit reached for this event',
        400,
      );
    }
  }

  private async tryEnhanceForOwner(
    imageUrl: string,
    eventId: string,
    uploaderId: string,
    ownerId: string,
    albumId?: string,
    prompt?: string,
    isPublished = true,
    sourceEventImageId?: string,
  ): Promise<
    EventImageDocument | { requestId: string; status: string } | null
  > {
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
          sourceEventImageId,
          isPublished,
        });
      }

      const enhancedUrl = await this.enhanceImage(imageUrl, finalPrompt);
      return await this.eventImageModel.create({
        eventId: this.toObjectId(eventId),
        imageUrl: enhancedUrl,
        userTakenBy: this.toObjectId(uploaderId),
        albumId: albumId ? this.toObjectId(albumId) : undefined,
        isEnhanced: true,
        enhancedFromId: sourceEventImageId
          ? this.toObjectId(sourceEventImageId)
          : undefined,
        isPublished,
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
      this.logger.warn(
        `fal-webhook-job-not-found requestId=${webhook.request_id}`,
      );
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
            error:
              webhook.error || webhook.payload_error || 'FAL request failed',
          },
        },
        { new: true },
      );

      if (failedJob) {
        await this.userModel.findByIdAndUpdate(job.ownerId, {
          $inc: { credits: job.creditsCharged },
        });
        void this.workflowWebhooks.publish(String(job.eventId), 'photo.ai', {
          sourceEventImageId: job.sourceEventImageId ? String(job.sourceEventImageId) : undefined,
          requestId: webhook.request_id,
          status: 'failed',
          error: webhook.error || webhook.payload_error || 'FAL request failed',
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
        enhancedFromId: job.sourceEventImageId,
        isPublished: job.isPublished !== false,
        falRequestId: webhook.request_id,
      });
      this.queuePhotoAutomation(eventImage);
      this.emitGallery(String(job.eventId), {
        type: 'photo.enhanced',
        imageId: String(eventImage._id),
        isPublished: eventImage.isPublished !== false,
      });
    }

    await this.falEnhancementJobModel.updateOne(
      { _id: job._id },
      {
        $set: { status: FalEnhancementJobStatus.COMPLETED },
        $unset: { error: '' },
      },
    );
    void this.workflowWebhooks.publish(String(job.eventId), 'photo.ai', {
      imageId: String(eventImage._id),
      sourceEventImageId: job.sourceEventImageId ? String(job.sourceEventImageId) : undefined,
      requestId: webhook.request_id,
      status: 'completed',
      isPublished: eventImage.isPublished !== false,
    });

    return {
      received: true,
      saved: true,
      eventImageId: String(eventImage._id),
    };
  }

  private async assertAlbumBelongsToEvent(albumId: string, eventId: string) {
    if (!Types.ObjectId.isValid(albumId)) {
      throw new HttpException('Invalid album id', 400);
    }

    const album = await this.albumModel
      .findById(albumId)
      .select('eventId albumId')
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
    const vectors = await this.faceVectorService.vectorsFromUrl(
      eventImage.imageUrl,
    );

    await this.qdrantFaceService.upsertFaces(vectors, {
      eventId: String(eventImage.eventId),
      eventImageId: String(eventImage._id),
      imageUrl: eventImage.imageUrl,
      isEnhanced: Boolean(eventImage.isEnhanced),
      albumId: eventImage.albumId ? String(eventImage.albumId) : undefined,
    });

    if (vectors.length) {
      await this.guestGalleryService.onPhotoIndexed(eventImage);
    }

    this.logger.log(
      `face-indexed image=${eventImage._id} faces=${vectors.length}`,
    );
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
    await this.eventMemberService.assertCanUpload(
      createEventImageDto.eventId,
      userId,
      role,
      createEventImageDto.albumId,
    );

    if (createEventImageDto.albumId) {
      await this.assertAlbumBelongsToEvent(
        createEventImageDto.albumId,
        createEventImageDto.eventId,
      );
    }

    if (createEventImageDto.clientTransferId) {
      const existing = await this.eventImageModel
        .findOne({
          eventId: this.toObjectId(createEventImageDto.eventId),
          clientTransferId: createEventImageDto.clientTransferId,
        })
        .exec();
      if (existing) {
        return {
          message: 'Event image already received',
          data: existing,
          enhancedData: null,
          enhancementJob: null,
          idempotent: true,
        };
      }
    }

    await this.assertEventUploadLimit(
      createEventImageDto.eventId,
      String(event.userId),
    );

    const publishPolicy = await this.resolvePublishPolicy(event, createEventImageDto.albumId);
    const publishOriginal = !event.requireReview &&
      (createEventImageDto.isEnhanced ? publishPolicy !== 'manual' : publishPolicy === 'auto_upload');
    const publishEnhanced = !event.requireReview && publishPolicy === 'auto_ai';
    let eventImage: EventImageDocument;
    try {
      eventImage = await this.eventImageModel.create({
        eventId: this.toObjectId(createEventImageDto.eventId),
        imageUrl: createEventImageDto.imageUrl,
        userTakenBy: this.toObjectId(String(userId)),
        albumId: createEventImageDto.albumId
          ? this.toObjectId(createEventImageDto.albumId)
          : undefined,
        isEnhanced: createEventImageDto.isEnhanced ?? false,
        mediaType: this.inferMediaType(createEventImageDto.imageUrl, createEventImageDto.mediaType),
        isPublished: publishOriginal,
        clientTransferId: createEventImageDto.clientTransferId,
      });
    } catch (error) {
      if (
        createEventImageDto.clientTransferId &&
        (error as { code?: number }).code === 11000
      ) {
        const existing = await this.eventImageModel
          .findOne({
            eventId: this.toObjectId(createEventImageDto.eventId),
            clientTransferId: createEventImageDto.clientTransferId,
          })
          .exec();
        if (existing) {
          return {
            message: 'Event image already received',
            data: existing,
            enhancedData: null,
            enhancementJob: null,
            idempotent: true,
          };
        }
      }
      throw error;
    }
    this.queuePhotoAutomation(eventImage);
    this.emitGallery(createEventImageDto.eventId, {
      type: 'photo.created',
      imageId: String(eventImage._id),
      isPublished: eventImage.isPublished !== false,
    });
    void this.workflowWebhooks.publish(createEventImageDto.eventId, 'photo.created', {
      imageId: String(eventImage._id),
      albumId: createEventImageDto.albumId,
      clientTransferId: createEventImageDto.clientTransferId,
      status: eventImage.isPublished !== false ? 'published' : 'processing',
      isPublished: eventImage.isPublished !== false,
    });

    let enhancedImage: EventImageDocument | null = null;
    let enhancementJob: { requestId: string; status: string } | null = null;
    if (event.autoEnhanceImages && !createEventImageDto.isEnhanced && createEventImageDto.mediaType !== 'video') {
      try {
        const enhancement = await this.tryEnhanceForOwner(
          createEventImageDto.imageUrl,
          createEventImageDto.eventId,
          String(userId),
          String(event.userId),
          createEventImageDto.albumId,
          createEventImageDto.enhancePrompt,
          publishEnhanced,
          String(eventImage._id),
        );
        if (enhancement && this.isEnhancementJobResult(enhancement)) {
          enhancementJob = enhancement;
        } else if (enhancement) {
          enhancedImage = enhancement as EventImageDocument;
          this.queuePhotoAutomation(enhancedImage);
          this.emitGallery(createEventImageDto.eventId, { type: 'photo.enhanced', imageId: String(enhancedImage._id), isPublished: enhancedImage.isPublished !== false });
          void this.workflowWebhooks.publish(createEventImageDto.eventId, 'photo.ai', { imageId: String(enhancedImage._id), sourceEventImageId: String(eventImage._id) });
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
    await this.eventMemberService.assertCanUpload(
      createEventImagesBatchDto.eventId,
      userId,
      role,
      createEventImagesBatchDto.albumId,
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

    const publishPolicy = await this.resolvePublishPolicy(event, createEventImagesBatchDto.albumId);
    const publishOriginal = !event.requireReview &&
      (createEventImagesBatchDto.isEnhanced ? publishPolicy !== 'manual' : publishPolicy === 'auto_upload');
    const publishEnhanced = !event.requireReview && publishPolicy === 'auto_ai';
    const docs = createEventImagesBatchDto.imageUrls.map((imageUrl) => ({
      eventId: this.toObjectId(createEventImagesBatchDto.eventId),
      imageUrl,
      userTakenBy: this.toObjectId(String(userId)),
      albumId: createEventImagesBatchDto.albumId
        ? this.toObjectId(createEventImagesBatchDto.albumId)
        : undefined,
      isEnhanced: createEventImagesBatchDto.isEnhanced ?? false,
      mediaType: this.inferMediaType(imageUrl, createEventImagesBatchDto.mediaType),
      isPublished: publishOriginal,
    }));

    const eventImages = await this.eventImageModel.insertMany(docs);
    eventImages.forEach((eventImage) => {
      this.queuePhotoAutomation(eventImage);
      void this.workflowWebhooks.publish(createEventImagesBatchDto.eventId, 'photo.created', {
        imageId: String(eventImage._id),
        albumId: createEventImagesBatchDto.albumId,
        isPublished: eventImage.isPublished !== false,
      });
    });
    this.emitGallery(createEventImagesBatchDto.eventId, {
      type: 'photos.created',
      imageIds: eventImages.map((image) => String(image._id)),
      count: eventImages.length,
      isPublished: publishOriginal,
    });

    let enhancedImages: EventImageDocument[] = [];
    let enhancementJobs: Array<{ requestId: string; status: string }> = [];
    if (event.autoEnhanceImages && !createEventImagesBatchDto.isEnhanced && createEventImagesBatchDto.mediaType !== 'video') {
      const results = await Promise.allSettled(
        createEventImagesBatchDto.imageUrls.map((imageUrl, index) =>
          this.tryEnhanceForOwner(
            imageUrl,
            createEventImagesBatchDto.eventId,
            String(userId),
            String(event.userId),
            createEventImagesBatchDto.albumId,
            createEventImagesBatchDto.enhancePrompt,
            publishEnhanced,
            eventImages[index] ? String(eventImages[index]._id) : undefined,
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

      enhancedImages.forEach((eventImage) => {
        this.queuePhotoAutomation(eventImage);
        void this.workflowWebhooks.publish(createEventImagesBatchDto.eventId, 'photo.ai', {
          imageId: String(eventImage._id),
          sourceEventImageId: eventImage.enhancedFromId ? String(eventImage.enhancedFromId) : undefined,
        });
      });
      if (enhancedImages.length) this.emitGallery(createEventImagesBatchDto.eventId, { type: 'photos.enhanced', imageIds: enhancedImages.map((image) => String(image._id)), count: enhancedImages.length });
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
      await this.galleryAccessService.assertFaceSearchAllowed(
        query.eventId,
        query.albumId,
        query.accessToken,
      );
    } else if (query.eventId) {
      await this.assertCanUseEvent(query.eventId, userId, role);
    }

    const { faces, vectors } =
      await this.faceVectorService.detectAndVectorFromBuffer(
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

    const limit = Math.min(Math.max(Number(query.limit) || 10000, 1), 10000);
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
      .sort(
        (a, b) =>
          (byImageId.get(b)?.score || 0) - (byImageId.get(a)?.score || 0),
      )
      .slice(0, limit);

    const data = await this.eventImageModel
      .find({
        _id: { $in: ids.map((id) => this.toObjectId(id)) },
        ...(query.eventId ? { eventId: this.toObjectId(query.eventId) } : {}),
        ...(query.albumId ? { albumId: this.toObjectId(query.albumId) } : {}),
        ...(publicAccess ? { isPublished: { $ne: false } } : {}),
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

    const response = {
      data: sortedData,
      totalItems: sortedData.length,
      faces,
    };
    if (!publicAccess || !query.eventId) return response;
    const protectedRows = await this.galleryAccessService.protectStoreOriginals(
      query.eventId,
      sortedData as Array<Record<string, any>>,
    );
    return { ...response, ...protectedRows };
  }

  async findAll(query: EventImageFilterDto, userId?: string, role?: string) {
    const page = Math.max(Number(query.page) || 1, 1);
    const limit = Math.min(Math.max(Number(query.limit) || 20, 1), 100);
    const skip = (page - 1) * limit;
    const filter: Record<string, unknown> = {};

    if (query.eventId) {
      await this.assertCanUseEvent(query.eventId, userId, role);
    }

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

  async facialBlurList(eventId: string, albumId?: string) {
    if (!eventId || !Types.ObjectId.isValid(eventId)) throw new HttpException('Invalid event id', 400);
    await this.galleryAccessService.assertFacialBlurPreview(eventId, albumId);
    const data = await this.eventImageModel.find({ eventId: this.toObjectId(eventId), isPublished: { $ne: false },
      mediaType: { $ne: 'video' }, ...(albumId ? { albumId: this.toObjectId(albumId) } : {}) })
      .select('_id createdAt').sort({ createdAt: -1 }).limit(250).lean();
    return { data: data.map((image) => ({ _id: String(image._id) })), totalItems: data.length };
  }

  async facialBlurImage(id: string, eventId: string, albumId?: string) {
    if (![id, eventId].every(Types.ObjectId.isValid)) throw new HttpException('Invalid preview id', 400);
    await this.galleryAccessService.assertFacialBlurPreview(eventId, albumId);
    const row = await this.eventImageModel.findOne({ _id: this.toObjectId(id), eventId: this.toObjectId(eventId),
      isPublished: { $ne: false }, mediaType: { $ne: 'video' }, ...(albumId ? { albumId: this.toObjectId(albumId) } : {}) })
      .select('imageUrl').lean();
    if (!row) throw new HttpException('Preview not found', 404);
    const response = await axios.get<ArrayBuffer>(row.imageUrl, { responseType: 'arraybuffer', timeout: 30000, maxContentLength: 50 * 1024 * 1024 });
    return sharp(Buffer.from(response.data)).rotate().resize({ width: 900, withoutEnlargement: true }).blur(24).jpeg({ quality: 48 }).toBuffer();
  }

  async findPublicByEvent(
    eventId: string,
    albumId?: string,
    accessToken?: string,
  ) {
    if (!eventId || !Types.ObjectId.isValid(eventId)) {
      throw new HttpException('Invalid event id', 400);
    }

    await this.galleryAccessService.assertCanView(
      eventId,
      albumId,
      accessToken,
    );

    if (albumId) {
      await this.assertAlbumBelongsToEvent(albumId, eventId);
    }

    const data = await this.eventImageModel
      .find({
        eventId: this.toObjectId(eventId),
        isPublished: { $ne: false },
        ...(albumId ? { albumId: this.toObjectId(albumId) } : {}),
      })
      .populate('eventId', 'title description image')
      .populate('albumId', 'title description')
      .populate('userTakenBy', 'name email phone userId role')
      .sort({ createdAt: -1 })
      .lean()
      .exec();

    const protectedRows = await this.galleryAccessService.protectStoreOriginals(
      eventId,
      data as Array<Record<string, any>>,
    );
    return { ...protectedRows, totalItems: protectedRows.data.length };
  }

  async findOne(id: string, userId?: string, role?: string) {
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
    const eventId =
      typeof eventImage.eventId === 'object' && eventImage.eventId?._id
        ? String(eventImage.eventId._id)
        : String(eventImage.eventId);
    await this.assertCanUseEvent(eventId, userId, role);

    return eventImage;
  }

  async setPublished(
    id: string,
    isPublished: boolean,
    userId?: string,
    role?: string,
  ) {
    if (!Types.ObjectId.isValid(id)) {
      throw new HttpException('Invalid event image id', 400);
    }
    const existing = await this.eventImageModel
      .findById(id)
      .select('eventId isPublished')
      .lean();
    if (!existing) throw new HttpException('Event image not found', 404);

    await this.eventMemberService.assertCanPublish(
      String(existing.eventId),
      userId,
      role,
    );
    const data = await this.eventImageModel
      .findByIdAndUpdate(id, { $set: { isPublished } }, { new: true })
      .populate('albumId', 'title description')
      .populate('userTakenBy', 'name email phone userId role')
      .lean();
    await this.transferStatusService.markPublication(
      String(existing.eventId),
      id,
      isPublished,
    );
    this.emitGallery(String(existing.eventId), {
      type: 'photo.visibility',
      imageId: id,
      isPublished,
    });
    void this.workflowWebhooks.publish(String(existing.eventId), 'photo.status', {
      imageId: id,
      status: isPublished ? 'published' : 'hidden',
      isPublished,
    });
    return {
      message: isPublished ? 'Image published' : 'Image unpublished',
      data,
    };
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
      .select('eventId albumId')
      .lean();

    if (!existing) {
      throw new HttpException('Event image not found', 400);
    }

    const eventId = updateEventImageDto.eventId ?? String(existing.eventId);
    await this.assertCanUseEvent(eventId, userId, role);
    await this.eventMemberService.assertCanUpload(
      eventId,
      userId,
      role,
      updateEventImageDto.albumId ??
        (existing.albumId ? String(existing.albumId) : undefined),
    );

    if (updateEventImageDto.albumId) {
      await this.assertAlbumBelongsToEvent(
        updateEventImageDto.albumId,
        eventId,
      );
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
      .select('eventId albumId')
      .lean();

    if (!existing) {
      throw new HttpException('Event image not found', 400);
    }

    await this.assertCanUseEvent(String(existing.eventId), userId, role);
    await this.eventMemberService.assertCanUpload(
      String(existing.eventId),
      userId,
      role,
      existing.albumId ? String(existing.albumId) : undefined,
    );
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
      .select('eventId imageUrl albumId isEnhanced isPublished mediaType')
      .lean();

    if (!existing) {
      throw new HttpException('Event image not found', 400);
    }
    if (existing.mediaType === 'video') throw new HttpException('AI photo enhancement is not available for video', 400);

    const event = await this.assertCanUseEvent(
      String(existing.eventId),
      userId,
      role,
    );
    await this.eventMemberService.assertCanUpload(
      String(existing.eventId),
      userId,
      role,
      existing.albumId ? String(existing.albumId) : undefined,
    );

    const enhancedImage = await this.tryEnhanceForOwner(
      existing.imageUrl,
      String(existing.eventId),
      String(userId),
      String(event.userId),
      existing.albumId ? String(existing.albumId) : undefined,
      prompt,
      !event.requireReview && ((await this.resolvePublishPolicy(event, existing.albumId ? String(existing.albumId) : undefined)) === 'auto_ai' || existing.isPublished !== false),
      String(existing._id),
    );

    if (!enhancedImage) {
      return {
        message: 'Enhance skipped because owner has not enough credits',
        data: null,
        skipped: true,
      };
    }

    if (!this.isEnhancementJobResult(enhancedImage)) {
      this.queuePhotoAutomation(enhancedImage);
      this.emitGallery(String(existing.eventId), { type: 'photo.enhanced', imageId: String(enhancedImage._id), isPublished: enhancedImage.isPublished !== false });
      void this.workflowWebhooks.publish(String(existing.eventId), 'photo.ai', { imageId: String(enhancedImage._id), sourceEventImageId: String(existing._id) });
    }

    return {
      message: 'Image enhanced successfully',
      data: enhancedImage,
      skipped: false,
    };
  }

  async enhancementJobs(eventId: string, userId?: string, role?: string) {
    await this.assertCanUseEvent(eventId, userId, role);
    const data = await this.falEnhancementJobModel.find({ eventId: this.toObjectId(eventId) })
      .populate('sourceEventImageId', 'imageUrl isPublished').sort({ createdAt: -1 }).limit(500).lean();
    return { data, totalItems: data.length };
  }

  async retryEnhancementJob(jobId: string, userId?: string, role?: string) {
    if (!Types.ObjectId.isValid(jobId)) throw new HttpException('Invalid enhancement job id', 400);
    const job = await this.falEnhancementJobModel.findById(jobId).lean();
    if (!job) throw new HttpException('Enhancement job not found', 404);
    if (job.status !== FalEnhancementJobStatus.FAILED) throw new HttpException('Only failed enhancement jobs can be retried', 400);
    const event = await this.assertCanUseEvent(String(job.eventId), userId, role);
    const result = await this.tryEnhanceForOwner(job.sourceImageUrl, String(job.eventId), String(job.uploaderId), String(event.userId),
      job.albumId ? String(job.albumId) : undefined, undefined, job.isPublished !== false, job.sourceEventImageId ? String(job.sourceEventImageId) : undefined);
    if (result && !this.isEnhancementJobResult(result)) {
      this.queuePhotoAutomation(result);
      this.emitGallery(String(job.eventId), { type: 'photo.enhanced', imageId: String(result._id), isPublished: result.isPublished !== false });
      void this.workflowWebhooks.publish(String(job.eventId), 'photo.ai', { imageId: String(result._id), sourceEventImageId: job.sourceEventImageId ? String(job.sourceEventImageId) : undefined });
    }
    return { message: result ? 'Enhancement retry started' : 'Enhancement retry skipped: insufficient credits', data: result };
  }

  async publishBatch(
    ids: string[],
    isPublished: boolean,
    userId?: string,
    role?: string,
  ) {
    const validIds = [...new Set(ids)].filter(Types.ObjectId.isValid);
    const rows = await this.eventImageModel
      .find({ _id: { $in: validIds.map((id) => this.toObjectId(id)) } })
      .select('_id eventId')
      .lean();
    const eventIds = [...new Set(rows.map((row) => String(row.eventId)))];
    for (const eventId of eventIds) {
      await this.eventMemberService.assertCanPublish(eventId, userId, role);
    }
    await this.eventImageModel.updateMany(
      { _id: { $in: rows.map((row) => row._id) } },
      { $set: { isPublished } },
    );
    await Promise.allSettled(
      rows.map((row) =>
        this.transferStatusService.markPublication(
          String(row.eventId),
          String(row._id),
          isPublished,
        ),
      ),
    );
    for (const eventId of eventIds) {
      const eventRows = rows.filter((row) => String(row.eventId) === eventId);
      this.emitGallery(eventId, {
        type: 'photos.visibility',
        imageIds: eventRows.map((row) => String(row._id)),
        isPublished,
      });
      eventRows.forEach((row) => {
        void this.workflowWebhooks.publish(eventId, 'photo.status', {
          imageId: String(row._id),
          status: isPublished ? 'published' : 'hidden',
          isPublished,
        });
      });
    }
    return {
      message: isPublished ? 'Images published' : 'Images hidden',
      updated: rows.length,
    };
  }

  async enhanceBatch(
    ids: string[],
    prompt: string | undefined,
    userId?: string,
    role?: string,
  ) {
    const validIds = [...new Set(ids)].filter(Types.ObjectId.isValid);
    const results = await Promise.allSettled(
      validIds.map((id) => this.enhanceExisting(id, userId, role, prompt)),
    );
    return {
      total: validIds.length,
      completed: results.filter((result) => result.status === 'fulfilled')
        .length,
      failed: results.filter((result) => result.status === 'rejected').length,
      results: results.map((result, index) => ({
        id: validIds[index],
        status: result.status,
        ...(result.status === 'fulfilled'
          ? { data: result.value }
          : { error: String(result.reason) }),
      })),
    };
  }

  async analyzeMedia(ids: string[], userId?: string, role?: string) {
    const validIds = [...new Set(ids)].filter(Types.ObjectId.isValid);
    const rows = await this.eventImageModel
      .find({ _id: { $in: validIds.map((id) => this.toObjectId(id)) } })
      .select('eventId')
      .lean();
    const eventIds = [...new Set(rows.map((row) => String(row.eventId)))];
    for (const eventId of eventIds) {
      await this.eventMemberService.assertCanAccess(eventId, userId, role);
    }
    return this.mediaAiService.analyzeMany(validIds);
  }

  async aiSearch(
    eventId: string,
    query: string,
    type: string,
    limit: number,
    userId?: string,
    role?: string,
  ) {
    await this.eventMemberService.assertCanAccess(eventId, userId, role);
    const data = await this.mediaAiService.search(eventId, query, type, limit);
    return { data, totalItems: data.length, type, query };
  }

  async reviewOverride(
    id: string,
    decision: 'approve' | 'reject' | 'clear',
    userId?: string,
    role?: string,
  ) {
    if (!Types.ObjectId.isValid(id))
      throw new HttpException('Invalid image id', 400);
    const row = await this.eventImageModel
      .findById(id)
      .select('eventId')
      .lean();
    if (!row) throw new HttpException('Event image not found', 404);
    await this.eventMemberService.assertCanPublish(
      String(row.eventId),
      userId,
      role,
    );
    if (decision === 'clear') {
      const data = await this.eventImageModel.findByIdAndUpdate(
        id,
        {
          $set: { aiReviewStatus: 'pending' },
          $unset: { reviewerDecision: '', reviewedBy: '', reviewedAt: '' },
        },
        { new: true },
      );
      this.mediaAiService.queueAnalysis(data!);
      return { message: 'AI review restored', data };
    }
    const data = await this.eventImageModel.findByIdAndUpdate(
      id,
      {
        $set: {
          reviewerDecision: decision,
          reviewedBy: this.toObjectId(String(userId)),
          reviewedAt: new Date(),
          aiReviewStatus: decision === 'approve' ? 'approved' : 'rejected',
        },
      },
      { new: true },
    );
    return { message: 'Review decision saved', data };
  }
}
