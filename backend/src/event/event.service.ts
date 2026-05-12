import { HttpException, Injectable, Logger } from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { Event, EventDocument } from './entities/event.entity';
import { Model, Types } from 'mongoose';
import { CreateEventDto, UpdateEventDto, EventFilterDto } from './dto/create-event.dto';

@Injectable()
export class EventService {
  private logger = new Logger(EventService.name);

  constructor(
    @InjectModel(Event.name)
    private eventModel: Model<EventDocument>,
  ) {}

  async create(createEventDto: CreateEventDto) {
    const normalizedUserId = String(createEventDto.userId);

    if (!Types.ObjectId.isValid(normalizedUserId)) {
      throw new HttpException('Invalid user id', 400);
    }

    const event = await this.eventModel.create({
      ...createEventDto,
      userId: new Types.ObjectId(normalizedUserId),
    });

    if (!event) {
      throw new HttpException('Event not created', 400);
    }
    return { message: 'Event created successfully', data: event };
  }

  async findAllByUser(userId?: string) {
    if (!userId) {
      return {
        data: [],
        page: 1,
        limit: 10,
        totalItems: 0,
        totalPages: 0,
        hasNextPage: false,
        hasPreviousPage: false,
      };
    }

    const normalizedUserId = String(userId);

    if (!Types.ObjectId.isValid(normalizedUserId)) {
      return {
        data: [],
        page: 1,
        limit: 10,
        totalItems: 0,
        totalPages: 0,
        hasNextPage: false,
        hasPreviousPage: false,
      };
    }

    const filter = {
      $or: [
        { userId: new Types.ObjectId(normalizedUserId) },
        { userId: normalizedUserId as any },
      ],
    };

    const [data, totalItems] = await Promise.all([
      this.eventModel
        .find(filter)
        .populate('userId', 'name email')
        .sort({ createdAt: -1 })
        .lean()
        .exec(),
      this.eventModel.countDocuments(filter).exec(),
    ]);

    return {
      data,
      page: 1,
      limit: 10,
      totalItems,
      totalPages: Math.ceil(totalItems / 10),
      hasNextPage: false,
      hasPreviousPage: false,
    };
  }

  async findAll(query: EventFilterDto) {
    const { query: searchQuery, page = 1, limit = 10, isPublished, isActive } = query;

    const skip = (page - 1) * limit;
    const filter: any = {};

    if (searchQuery) {
      filter.$or = [
        { title: { $regex: searchQuery, $options: 'i' } },
        { description: { $regex: searchQuery, $options: 'i' } },
      ];
    }

    if (isPublished !== undefined && isPublished !== 'all') {
      filter.isPublished = isPublished === 'true';
    }

    if (isActive !== undefined && isActive !== 'all') {
      filter.isActive = isActive === 'true';
    }

    const [data, totalItems] = await Promise.all([
      this.eventModel
        .find(filter)
        .populate('userId', 'name email')
        .skip(skip)
        .limit(limit)
        .sort({ createdAt: -1 })
        .lean()
        .exec(),
      this.eventModel.countDocuments(filter).exec(),
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

  async findOne(id: string) {
    const event = await this.eventModel
      .findById(id)
      .populate('userId', 'name email phone')
      .lean();

    if (!event) {
      throw new HttpException('Event not found', 400);
    }

    return event;
  }

  async update(id: string, updateEventDto: UpdateEventDto) {
    const shouldUnsetImage =
      updateEventDto.image &&
      !updateEventDto.image.url &&
      !updateEventDto.image.publicId;

    const event = await this.eventModel
      .findByIdAndUpdate(
        id,
        shouldUnsetImage
          ? {
              $set: {
                ...updateEventDto,
                image: undefined,
              },
              $unset: { image: '' },
            }
          : { $set: updateEventDto },
        { new: true },
      )
      .lean();

    if (!event) {
      throw new HttpException('Event not found', 400);
    }

    return { message: 'Event updated successfully', data: event };
  }

  async remove(id: string) {
    const event = await this.eventModel.findByIdAndDelete(id).lean();

    if (!event) {
      throw new HttpException('Event not found', 400);
    }

    return { message: 'Event deleted successfully', data: event };
  }

  async toggleActive(id: string, userId?: string) {
    const event = await this.eventModel.findById(id).select('isActive userId').lean();

    if (!event) {
      throw new HttpException('Event not found', 400);
    }

    if (userId && String(event.userId) !== userId) {
      throw new HttpException('You can only modify your own events', 403);
    }

    const updated = await this.eventModel
      .findByIdAndUpdate(id, { $set: { isActive: !event.isActive } }, { new: true })
      .lean();

    return updated;
  }

  async togglePublished(id: string, userId?: string) {
    const event = await this.eventModel.findById(id).select('isPublished userId').lean();

    if (!event) {
      throw new HttpException('Event not found', 400);
    }

    if (userId && String(event.userId) !== userId) {
      throw new HttpException('You can only modify your own events', 403);
    }

    const updated = await this.eventModel
      .findByIdAndUpdate(id, { $set: { isPublished: !event.isPublished } }, { new: true })
      .lean();

    return updated;
  }
}
