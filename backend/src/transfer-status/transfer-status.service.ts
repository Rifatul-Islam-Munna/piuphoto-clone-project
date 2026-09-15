import { Injectable, MessageEvent } from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { Model, Types } from 'mongoose';
import { Observable, Subject, interval, map, merge } from 'rxjs';
import { EventMemberService } from '../event-member/event-member.service';
import { UploadSessionService } from '../upload-session/upload-session.service';
import {
  TransferStatusQueryDto,
  UpsertTransferStatusDto,
} from './dto/transfer-status.dto';
import {
  PhotoTransferState,
  PhotoTransferStatus,
  PhotoTransferStatusDocument,
} from './entities/photo-transfer-status.entity';

@Injectable()
export class TransferStatusService {
  private readonly streams = new Map<
    string,
    Subject<Record<string, unknown>>
  >();

  constructor(
    @InjectModel(PhotoTransferStatus.name)
    private readonly model: Model<PhotoTransferStatusDocument>,
    private readonly eventMembers: EventMemberService,
    private readonly uploadSessions: UploadSessionService,
  ) {}

  private subject(eventId: string) {
    let subject = this.streams.get(eventId);
    if (!subject) {
      subject = new Subject<Record<string, unknown>>();
      this.streams.set(eventId, subject);
    }
    return subject;
  }

  private toObjectId(id?: string) {
    return id && Types.ObjectId.isValid(id)
      ? new Types.ObjectId(id)
      : undefined;
  }

  async upsert(dto: UpsertTransferStatusDto, userId: string, role?: string) {
    await this.eventMembers.assertCanUpload(
      dto.eventId,
      userId,
      role,
      dto.albumId,
    );
    const session = await this.uploadSessions.touchFromTransfer({
      eventId: dto.eventId,
      photographerId: userId,
      albumId: dto.albumId,
      source: dto.source,
      cameraId: dto.cameraId,
      transferStarted: dto.status === PhotoTransferState.DETECTED,
    });
    const now = new Date();
    const timestamps: Record<string, Date> = {};
    if (
      [
        PhotoTransferState.PROCESSING,
        PhotoTransferState.PUBLISHED,
        PhotoTransferState.DELIVERED,
      ].includes(dto.status)
    ) {
      timestamps.uploadedAt = now;
    }
    if (
      [PhotoTransferState.DELIVERED, PhotoTransferState.PUBLISHED].includes(
        dto.status,
      )
    ) {
      timestamps.uploadedAt = now;
      timestamps.deliveredAt = now;
    }

    const data = await this.model
      .findOneAndUpdate(
        {
          eventId: this.toObjectId(dto.eventId),
          clientTransferId: dto.clientTransferId,
        },
        {
          $setOnInsert: {
            photographerId: this.toObjectId(userId),
            capturedAt: now,
          },
          $set: {
            filename: dto.filename,
            source: dto.source || 'camera',
            cameraId: dto.cameraId,
            mediaType: dto.mediaType || 'photo',
            albumId: this.toObjectId(dto.albumId),
            uploadSessionId: session?._id,
            status: dto.status,
            progress: dto.progress ?? 0,
            bytesSent: dto.bytesSent ?? 0,
            bytesTotal: dto.bytesTotal ?? 0,
            bytesPerSecond: dto.bytesPerSecond ?? 0,
            error: dto.error || undefined,
            imageUrl: dto.imageUrl || undefined,
            eventImageId: this.toObjectId(dto.eventImageId),
            ...timestamps,
          },
        },
        { upsert: true, new: true, setDefaultsOnInsert: true },
      )
      .populate('photographerId', 'name email userId profileImage')
      .populate('albumId', 'title')
      .populate('uploadSessionId', 'source cameraId startedAt lastSeenAt status')
      .lean();

    const payload = { type: 'transfer.updated', data };
    this.subject(dto.eventId).next(payload as Record<string, unknown>);
    return { message: 'Transfer status updated', data };
  }

  async list(query: TransferStatusQueryDto, userId: string, role?: string) {
    await this.eventMembers.assertCanAccess(query.eventId, userId, role);
    const eventId = this.toObjectId(query.eventId);
    const filter: Record<string, unknown> = { eventId };
    if (query.status) filter.status = query.status;
    const limit = Math.min(Math.max(query.limit || 200, 1), 1000);

    const [data, counts] = await Promise.all([
      this.model
        .find(filter)
        .populate('photographerId', 'name email userId profileImage')
        .populate('albumId', 'title')
        .populate('uploadSessionId', 'source cameraId startedAt lastSeenAt status')
        .sort({ createdAt: -1 })
        .limit(limit)
        .lean(),
      this.model.aggregate<{ _id: string; count: number }>([
        { $match: { eventId } },
        { $group: { _id: '$status', count: { $sum: 1 } } },
      ]),
    ]);

    const summary = Object.fromEntries(
      counts.map((item) => [item._id, item.count]),
    );
    return {
      data,
      totalItems: counts.reduce((sum, item) => sum + item.count, 0),
      summary,
    };
  }

  async markPublication(
    eventId: string,
    eventImageId: string,
    isPublished: boolean,
  ) {
    if (!Types.ObjectId.isValid(eventId) || !Types.ObjectId.isValid(eventImageId)) {
      return null;
    }
    const now = new Date();
    const data = await this.model
      .findOneAndUpdate(
        {
          eventId: this.toObjectId(eventId),
          eventImageId: this.toObjectId(eventImageId),
        },
        {
          $set: {
            status: isPublished
              ? PhotoTransferState.PUBLISHED
              : PhotoTransferState.PROCESSING,
            progress: 100,
            ...(isPublished ? { deliveredAt: now } : {}),
          },
        },
        { new: true },
      )
      .populate('photographerId', 'name email userId profileImage')
      .populate('albumId', 'title')
      .populate('uploadSessionId', 'source cameraId startedAt lastSeenAt status')
      .lean();
    if (data) {
      this.subject(eventId).next({ type: 'transfer.updated', data });
    }
    return data;
  }

  async stream(
    eventId: string,
    userId: string,
    role?: string,
  ): Promise<Observable<MessageEvent>> {
    await this.eventMembers.assertCanAccess(eventId, userId, role);
    const updates = this.subject(eventId)
      .asObservable()
      .pipe(
        map((payload) => ({ type: 'transfer', data: payload }) as MessageEvent),
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
}
