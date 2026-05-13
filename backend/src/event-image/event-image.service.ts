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
import { UserType } from '../user/entities/user.entity';

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

  private enhancePrompt() {
    return [
      'Professional Adobe Photoshop-style photo enhancement.',
      'Preserve the original subject identity, pose, clothing, scene, and composition.',
      'Correct red-eye, closed or half-closed eyes, harsh flash, blur, low light, shadows, skin tone, white balance, exposure, and noise.',
      'Improve sharpness, facial details, natural eyes, color grading, dynamic range, and event photography polish.',
      'Keep the image realistic and natural. Do not add new people, objects, text, logos, watermarks, or change the event context.',
    ].join(' ');
  }

  private async enhanceImage(imageUrl: string) {
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
        prompt: this.enhancePrompt(),
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
        const enhancedUrl = await this.enhanceImage(createEventImageDto.imageUrl);
        enhancedImage = await this.eventImageModel.create({
          eventId: this.toObjectId(createEventImageDto.eventId),
          imageUrl: enhancedUrl,
          userTakenBy: this.toObjectId(String(userId)),
          albumId: createEventImageDto.albumId
            ? this.toObjectId(createEventImageDto.albumId)
            : undefined,
          isEnhanced: true,
        });
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

    const data = await this.eventImageModel
      .find(filter)
      .populate('eventId', 'title description image')
      .populate('albumId', 'title description')
      .populate('userTakenBy', 'name email phone userId role')
      .sort({ createdAt: -1 })
      .lean()
      .exec();

    return { data, totalItems: data.length };
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
}
