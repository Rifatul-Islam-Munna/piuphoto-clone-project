import { Injectable } from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { Model, Types } from 'mongoose';
import { EventMemberService } from '../event-member/event-member.service';
import {
  UploadSession,
  UploadSessionDocument,
  UploadSessionStatus,
} from './entities/upload-session.entity';

export type TouchUploadSessionInput = {
  eventId: string;
  photographerId: string;
  albumId?: string;
  source?: string;
  cameraId?: string;
  transferStarted?: boolean;
};

@Injectable()
export class UploadSessionService {
  private static readonly activeWindowMs = 45 * 60 * 1000;

  constructor(
    @InjectModel(UploadSession.name)
    private readonly model: Model<UploadSessionDocument>,
    private readonly eventMembers: EventMemberService,
  ) {}

  private toObjectId(id?: string) {
    return id && Types.ObjectId.isValid(id) ? new Types.ObjectId(id) : undefined;
  }

  async touchFromTransfer(input: TouchUploadSessionInput) {
    const eventId = this.toObjectId(input.eventId);
    const photographerId = this.toObjectId(input.photographerId);
    if (!eventId || !photographerId) return null;

    const now = new Date();
    const cutoff = new Date(now.getTime() - UploadSessionService.activeWindowMs);
    const source = input.source?.trim() || 'camera';
    const cameraId = input.cameraId?.trim() || undefined;
    const albumId = this.toObjectId(input.albumId);

    const filter: Record<string, unknown> = {
      eventId,
      photographerId,
      source,
      status: UploadSessionStatus.ACTIVE,
      lastSeenAt: { $gte: cutoff },
    };
    if (cameraId) filter.cameraId = cameraId;
    else filter.cameraId = { $in: [null, ''] };
    if (albumId) filter.albumId = albumId;
    else filter.albumId = { $exists: false };

    const existing = await this.model
      .findOne(filter)
      .sort({ lastSeenAt: -1 })
      .exec();

    if (existing) {
      existing.lastSeenAt = now;
      if (input.transferStarted) existing.transferCount += 1;
      await existing.save();
      return existing;
    }

    return this.model.create({
      eventId,
      photographerId,
      albumId,
      source,
      cameraId,
      status: UploadSessionStatus.ACTIVE,
      startedAt: now,
      lastSeenAt: now,
      transferCount: input.transferStarted ? 1 : 0,
    });
  }

  async listForEvent(eventId: string, userId?: string, role?: string) {
    await this.eventMembers.assertCanAccess(eventId, userId, role);
    const objectId = this.toObjectId(eventId);
    if (!objectId) return { data: [], totalItems: 0, activeItems: 0 };

    const now = Date.now();
    const activeCutoff = new Date(now - UploadSessionService.activeWindowMs);
    await this.model.updateMany(
      {
        eventId: objectId,
        status: UploadSessionStatus.ACTIVE,
        lastSeenAt: { $lt: activeCutoff },
      },
      { $set: { status: UploadSessionStatus.ENDED, endedAt: new Date() } },
    );

    const data = await this.model
      .find({ eventId: objectId })
      .populate('photographerId', 'name email userId profileImage')
      .populate('albumId', 'title')
      .sort({ lastSeenAt: -1 })
      .limit(200)
      .lean();

    const enriched = data.map((session) => ({
      ...session,
      isLive:
        session.status === UploadSessionStatus.ACTIVE &&
        new Date(session.lastSeenAt).getTime() >= activeCutoff.getTime(),
    }));

    return {
      data: enriched,
      totalItems: enriched.length,
      activeItems: enriched.filter((session) => session.isLive).length,
    };
  }
}
