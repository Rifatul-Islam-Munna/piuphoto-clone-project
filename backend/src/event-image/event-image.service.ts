import { HttpException, Injectable } from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { Model, Types } from 'mongoose';
import {
  CreateEventImageDto,
  EventImageFilterDto,
} from './dto/create-event-image.dto';
import { UpdateEventImageDto } from './dto/update-event-image.dto';
import { EventImage, EventImageDocument } from './entities/event-image.entity';
import { Event, EventDocument } from '../event/entities/event.entity';
import {
  EventInvitation,
  EventInvitationDocument,
  EventInvitationStatus,
} from '../event/entities/event-invitation.entity';
import { UserType } from '../user/entities/user.entity';

@Injectable()
export class EventImageService {
  constructor(
    @InjectModel(EventImage.name)
    private eventImageModel: Model<EventImageDocument>,
    @InjectModel(Event.name)
    private eventModel: Model<EventDocument>,
    @InjectModel(EventInvitation.name)
    private eventInvitationModel: Model<EventInvitationDocument>,
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
      .select('userId title')
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

  async create(
    createEventImageDto: CreateEventImageDto,
    userId?: string,
    role?: string,
  ) {
    await this.assertCanUseEvent(createEventImageDto.eventId, userId, role);

    const eventImage = await this.eventImageModel.create({
      eventId: this.toObjectId(createEventImageDto.eventId),
      imageUrl: createEventImageDto.imageUrl,
      userTakenBy: this.toObjectId(String(userId)),
      referenceId: createEventImageDto.referenceId?.trim() || undefined,
      isEnhanced: createEventImageDto.isEnhanced ?? false,
    });

    return { message: 'Event image created successfully', data: eventImage };
  }

  async findAll(query: EventImageFilterDto) {
    const filter: Record<string, unknown> = {};

    if (query.eventId && Types.ObjectId.isValid(query.eventId)) {
      filter.eventId = this.toObjectId(query.eventId);
    }

    if (query.userTakenBy && Types.ObjectId.isValid(query.userTakenBy)) {
      filter.userTakenBy = this.toObjectId(query.userTakenBy);
    }

    if (query.referenceId) {
      filter.referenceId = query.referenceId;
    }

    if (query.isEnhanced !== undefined && query.isEnhanced !== 'all') {
      filter.isEnhanced = query.isEnhanced === 'true';
    }

    const data = await this.eventImageModel
      .find(filter)
      .populate('eventId', 'title description image')
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

    const update: Record<string, unknown> = { ...updateEventImageDto };
    if (updateEventImageDto.eventId) {
      update.eventId = this.toObjectId(updateEventImageDto.eventId);
    }
    if (updateEventImageDto.referenceId !== undefined) {
      update.referenceId = updateEventImageDto.referenceId.trim() || undefined;
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
