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
    const event = await this.eventModel.create(createEventDto);
    if (!event) {
      throw new HttpException('Event not created', 400);
    }
    return { message: 'Event created successfully', data: event };
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
    const event = await this.eventModel
      .findByIdAndUpdate(id, { $set: updateEventDto }, { new: true })
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

  async toggleActive(id: string) {
    const event = await this.eventModel.findById(id).select('isActive').lean();

    if (!event) {
      throw new HttpException('Event not found', 400);
    }

    const updated = await this.eventModel
      .findByIdAndUpdate(id, { $set: { isActive: !event.isActive } }, { new: true })
      .lean();

    return updated;
  }

  async togglePublished(id: string) {
    const event = await this.eventModel.findById(id).select('isPublished').lean();

    if (!event) {
      throw new HttpException('Event not found', 400);
    }

    const updated = await this.eventModel
      .findByIdAndUpdate(id, { $set: { isPublished: !event.isPublished } }, { new: true })
      .lean();

    return updated;
  }
}