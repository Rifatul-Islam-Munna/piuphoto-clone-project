import { HttpException, Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import axios from 'axios';
import { InjectModel } from '@nestjs/mongoose';
import { Model, Types } from 'mongoose';
import {
  CreateEventImageDto,
  EventImageFilterDto,
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

@Injectable()
export class EventImageService {
  private readonly logger = new Logger(EventImageService.name);

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
    private readonly configService: ConfigService,
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
      'Professional Adobe Photoshop-style photo enhancement.',
      'Preserve the original subject identity, pose, clothing, scene, and composition.',
      'Correct red-eye, closed or half-closed eyes, harsh flash, blur, low light, shadows, skin tone, white balance, exposure, and noise.',
      'Improve sharpness, facial details, natural eyes, color grading, dynamic range, and event photography polish.',
      'Keep the image realistic and natural. Do not add new people, objects, text, logos, watermarks, or change the event context.',
    ].join(' ');
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
        prompt: prompt?.trim() || this.defaultEnhancePrompt(),
        image_urls: [imageUrl],
        image_size: 'auto',
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

  private async assertEventUploadLimit(eventId: string, ownerId: string) {
    const meta = await this.getOwnerPlanMeta(ownerId);
    if (meta.monthlyPhotoLimit <= 0) return;

    const currentCount = await this.eventImageModel.countDocuments({
      eventId: this.toObjectId(eventId),
      isEnhanced: { $ne: true },
    });

    if (currentCount >= meta.monthlyPhotoLimit) {
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
  ) {
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

    let enhancedImage: EventImageDocument | null = null;
    if (event.autoEnhanceImages && !createEventImageDto.isEnhanced) {
      try {
        enhancedImage = await this.tryEnhanceForOwner(
          createEventImageDto.imageUrl,
          createEventImageDto.eventId,
          String(userId),
          String(event.userId),
          createEventImageDto.albumId,
          createEventImageDto.enhancePrompt,
        );
      } catch (error) {
        this.logger.error('image-enhance-failed', error);
      }
    }

    return {
      message: 'Event image created successfully',
      data: eventImage,
      enhancedData: enhancedImage,
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
