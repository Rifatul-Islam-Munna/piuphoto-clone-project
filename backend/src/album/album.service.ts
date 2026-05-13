import { HttpException, Injectable } from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { Model, Types } from 'mongoose';
import { UserType } from '../user/entities/user.entity';
import { Event, EventDocument } from '../event/entities/event.entity';
import {
  EventImage,
  EventImageDocument,
} from '../event-image/entities/event-image.entity';
import { Album, AlbumDocument } from './entities/album.entity';
import { AlbumFilterDto, CreateAlbumDto, UpdateAlbumDto } from './dto/album.dto';

@Injectable()
export class AlbumService {
  constructor(
    @InjectModel(Album.name) private albumModel: Model<AlbumDocument>,
    @InjectModel(Event.name) private eventModel: Model<EventDocument>,
    @InjectModel(EventImage.name)
    private eventImageModel: Model<EventImageDocument>,
  ) {}

  private toObjectId(id: string) {
    return new Types.ObjectId(id);
  }

  private async getOwnedEvent(eventId: string, userId?: string, role?: string) {
    if (!Types.ObjectId.isValid(eventId)) {
      throw new HttpException('Invalid event id', 400);
    }

    const event = await this.eventModel
      .findById(eventId)
      .select('userId title')
      .lean();

    if (!event) {
      throw new HttpException('Event not found', 404);
    }

    if (role !== UserType.ADMIN && String(event.userId) !== userId) {
      throw new HttpException('You can only manage your own event albums', 403);
    }

    return event;
  }

  async create(dto: CreateAlbumDto, userId?: string, role?: string) {
    const event = await this.getOwnedEvent(dto.eventId, userId, role);
    const album = await this.albumModel.create({
      title: dto.title,
      description: dto.description,
      eventId: this.toObjectId(dto.eventId),
      userId: this.toObjectId(String(event.userId)),
    });

    return { message: 'Album created successfully', data: album };
  }

  async findAll(query: AlbumFilterDto) {
    const filter: Record<string, unknown> = {};

    if (query.eventId && Types.ObjectId.isValid(query.eventId)) {
      filter.eventId = this.toObjectId(query.eventId);
    }

    const data = await this.albumModel
      .find(filter)
      .populate('eventId', 'title description image')
      .sort({ createdAt: -1 })
      .lean();

    return { data: await this.withImageCounts(data), totalItems: data.length };
  }

  async findPublicByEvent(eventId: string) {
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

    const data = await this.albumModel
      .find({ eventId: this.toObjectId(eventId) })
      .populate('eventId', 'title description image')
      .sort({ createdAt: -1 })
      .lean();

    return { data: await this.withImageCounts(data), totalItems: data.length };
  }

  private async withImageCounts<T extends { _id: unknown }>(albums: T[]) {
    if (!albums.length) {
      return albums.map((album) => ({ ...album, imagesCount: 0 }));
    }

    const ids = albums.map((album) => this.toObjectId(String(album._id)));
    const counts = await this.eventImageModel
      .aggregate<{ _id: Types.ObjectId; count: number }>([
        { $match: { albumId: { $in: ids } } },
        { $group: { _id: '$albumId', count: { $sum: 1 } } },
      ])
      .exec();
    const countMap = new Map(counts.map((item) => [String(item._id), item.count]));

    return albums.map((album) => ({
      ...album,
      imagesCount: countMap.get(String(album._id)) ?? 0,
    }));
  }

  async update(
    id: string,
    dto: UpdateAlbumDto,
    userId?: string,
    role?: string,
  ) {
    if (!Types.ObjectId.isValid(id)) {
      throw new HttpException('Invalid album id', 400);
    }

    const album = await this.albumModel.findById(id).select('eventId').lean();
    if (!album) {
      throw new HttpException('Album not found', 404);
    }

    await this.getOwnedEvent(String(album.eventId), userId, role);
    const updated = await this.albumModel
      .findByIdAndUpdate(id, { $set: dto }, { new: true })
      .lean();

    return { message: 'Album updated successfully', data: updated };
  }

  async remove(id: string, userId?: string, role?: string) {
    if (!Types.ObjectId.isValid(id)) {
      throw new HttpException('Invalid album id', 400);
    }

    const album = await this.albumModel.findById(id).select('eventId').lean();
    if (!album) {
      throw new HttpException('Album not found', 404);
    }

    await this.getOwnedEvent(String(album.eventId), userId, role);
    const deleted = await this.albumModel.findByIdAndDelete(id).lean();
    await this.eventImageModel.updateMany(
      { albumId: this.toObjectId(id) },
      { $unset: { albumId: '' } },
    );

    return { message: 'Album deleted successfully', data: deleted };
  }
}
