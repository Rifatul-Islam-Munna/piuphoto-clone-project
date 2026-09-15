import { HttpException, Injectable } from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { Model, Types } from 'mongoose';
import { UserType } from '../user/entities/user.entity';
import { Event, EventDocument } from '../event/entities/event.entity';
import { EventMemberService } from '../event-member/event-member.service';
import { GalleryAccessService } from '../gallery-access/gallery-access.service';
import {
  EventImage,
  EventImageDocument,
} from '../event-image/entities/event-image.entity';
import { Album, AlbumDocument } from './entities/album.entity';
import {
  AlbumFilterDto,
  CreateAlbumDto,
  UpdateAlbumDto,
} from './dto/album.dto';

@Injectable()
export class AlbumService {
  constructor(
    @InjectModel(Album.name) private albumModel: Model<AlbumDocument>,
    @InjectModel(Event.name) private eventModel: Model<EventDocument>,
    @InjectModel(EventImage.name)
    private eventImageModel: Model<EventImageDocument>,
    private readonly eventMemberService: EventMemberService,
    private readonly galleryAccessService: GalleryAccessService,
  ) {}

  private toObjectId(id: string) {
    return new Types.ObjectId(id);
  }

  private async getOwnedEvent(eventId: string, userId?: string, role?: string) {
    return this.eventMemberService.assertCanManage(eventId, userId, role);
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

  async findAll(query: AlbumFilterDto, userId?: string, role?: string) {
    const filter: Record<string, unknown> = {};

    if (query.eventId) {
      await this.eventMemberService.assertCanAccess(
        query.eventId,
        userId,
        role,
      );
      const allowedAlbumIds = await this.eventMemberService.allowedAlbumIds(
        query.eventId,
        userId,
        role,
      );
      if (allowedAlbumIds) {
        filter._id = {
          $in: allowedAlbumIds.map((id) => this.toObjectId(id)),
        };
      }
    }

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

  async findPublicByEvent(eventId: string, accessToken?: string) {
    if (!eventId || !Types.ObjectId.isValid(eventId)) {
      throw new HttpException('Invalid event id', 400);
    }

    await this.galleryAccessService.assertCanView(
      eventId,
      undefined,
      accessToken,
    );

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
      .aggregate<{
        _id: Types.ObjectId;
        count: number;
      }>([
        { $match: { albumId: { $in: ids } } },
        { $group: { _id: '$albumId', count: { $sum: 1 } } },
      ])
      .exec();
    const countMap = new Map(
      counts.map((item) => [String(item._id), item.count]),
    );

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
