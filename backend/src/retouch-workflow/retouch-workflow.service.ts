import { ForbiddenException, HttpException, Injectable, MessageEvent } from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { Model, Types } from 'mongoose';
import { Observable, Subject, interval, map, merge } from 'rxjs';
import { EventMemberService } from '../event-member/event-member.service';
import { EventMember, EventMemberDocument, EventMemberRole, EventMemberStatus } from '../event-member/entities/event-member.entity';
import { Event, EventDocument } from '../event/entities/event.entity';
import { EventImage, EventImageDocument } from '../event-image/entities/event-image.entity';
import { UserType } from '../user/entities/user.entity';
import { TransferStatusService } from '../transfer-status/transfer-status.service';
import { WorkflowWebhookPublisherService } from '../external-api/workflow-webhook-publisher.service';
import { AssignRetouchDto, BulkReviewRetouchDto, DesktopFeedDto, RetouchListDto, RetouchSettingsDto, RetouchStatusDto, RetouchVersionDto, ReviewRetouchDto } from './dto/retouch.dto';
import { PhotoVersion, PhotoVersionDocument } from './entities/photo-version.entity';
import { RetouchJob, RetouchJobDocument, RetouchJobStatus } from './entities/retouch-job.entity';
import { RetouchWorkflowSettings, RetouchWorkflowSettingsDocument } from './entities/retouch-workflow-settings.entity';

@Injectable()
export class RetouchWorkflowService {
  private readonly streams = new Map<string, Subject<Record<string, unknown>>>();
  constructor(
    @InjectModel(RetouchJob.name) private readonly jobs: Model<RetouchJobDocument>,
    @InjectModel(PhotoVersion.name) private readonly versionsModel: Model<PhotoVersionDocument>,
    @InjectModel(RetouchWorkflowSettings.name) private readonly settingsModel: Model<RetouchWorkflowSettingsDocument>,
    @InjectModel(EventImage.name) private readonly images: Model<EventImageDocument>,
    @InjectModel(Event.name) private readonly events: Model<EventDocument>,
    @InjectModel(EventMember.name) private readonly membersModel: Model<EventMemberDocument>,
    private readonly members: EventMemberService,
    private readonly transfers: TransferStatusService,
    private readonly webhooks: WorkflowWebhookPublisherService,
  ) {}

  private oid(value: string | Types.ObjectId) {
    if (!Types.ObjectId.isValid(String(value))) throw new HttpException('Invalid id', 400);
    return new Types.ObjectId(String(value));
  }
  private subject(eventId: string) {
    let stream = this.streams.get(eventId);
    if (!stream) { stream = new Subject<Record<string, unknown>>(); this.streams.set(eventId, stream); }
    return stream;
  }
  private emit(eventId: string, type: string, data: unknown) {
    this.subject(eventId).next({ type, data, at: new Date().toISOString() });
  }

  async registerIncoming(image: EventImageDocument | Record<string, any>) {
    if (!image?._id || !image?.eventId || image.mediaType === 'video' || image.isEnhanced === true) return null;
    const eventId = String(image.eventId);
    const eventImageId = String(image._id);
    const job = await this.jobs.findOneAndUpdate(
      { eventImageId: this.oid(eventImageId) },
      { $setOnInsert: {
        eventId: this.oid(eventId), eventImageId: this.oid(eventImageId),
        albumId: image.albumId ? this.oid(String(image.albumId)) : undefined,
        photographerId: image.userTakenBy ? this.oid(String(image.userTakenBy)) : undefined,
        originalImageUrl: image.imageUrl, currentImageUrl: image.imageUrl,
        status: RetouchJobStatus.INCOMING,
      } },
      { upsert: true, new: true, setDefaultsOnInsert: true },
    ).lean();
    await this.versionsModel.updateOne(
      { eventImageId: this.oid(eventImageId), version: 1 },
      { $setOnInsert: { eventId: this.oid(eventId), eventImageId: this.oid(eventImageId), version: 1, type: 'original', imageUrl: image.imageUrl, createdBy: image.userTakenBy } },
      { upsert: true },
    );
    this.emit(eventId, 'retouch.incoming', job);
    return job;
  }

  private async actor(eventId: string, userId?: string, globalRole?: string) {
    if (!userId || !Types.ObjectId.isValid(userId)) throw new ForbiddenException('Login required');
    const event = await this.events.findById(eventId).select('userId title').lean();
    if (!event) throw new HttpException('Event not found', 404);
    if (globalRole === UserType.ADMIN || String(event.userId) === userId) return { event, role: EventMemberRole.OWNER };
    const membership = await this.membersModel.findOne({ eventId: this.oid(eventId), userId: this.oid(userId), status: EventMemberStatus.ACTIVE }).select('role').lean();
    if (!membership) throw new ForbiddenException('Event access denied');
    return { event, role: membership.role };
  }
  private async assertManager(eventId: string, userId?: string, globalRole?: string) {
    const actor = await this.actor(eventId, userId, globalRole);
    if (![EventMemberRole.OWNER, EventMemberRole.EVENT_PLANNER].includes(actor.role)) throw new ForbiddenException('Owner or planner required');
    return actor;
  }
  private async assertReviewer(eventId: string, userId?: string, globalRole?: string) {
    const actor = await this.actor(eventId, userId, globalRole);
    if (![EventMemberRole.OWNER, EventMemberRole.EVENT_PLANNER, EventMemberRole.REVIEWER].includes(actor.role)) throw new ForbiddenException('Reviewer access required');
    return actor;
  }
  private async assertRetoucher(eventId: string, userId?: string, globalRole?: string) {
    const actor = await this.actor(eventId, userId, globalRole);
    if (![EventMemberRole.OWNER, EventMemberRole.EVENT_PLANNER, EventMemberRole.RETOUCHER].includes(actor.role)) throw new ForbiddenException('Retoucher access required');
    return actor;
  }

  async list(query: RetouchListDto, userId?: string, globalRole?: string) {
    const actor = await this.actor(query.eventId, userId, globalRole);
    const filter: Record<string, unknown> = { eventId: this.oid(query.eventId) };
    if (query.status) filter.status = query.status;
    if (query.albumId) filter.albumId = this.oid(query.albumId);
    if (query.photographerId) filter.photographerId = this.oid(query.photographerId);
    if (query.retoucherId) filter.assignedRetoucherId = this.oid(query.retoucherId);
    const createdAt: Record<string, Date> = {};
    if (query.from) { const value = new Date(query.from); if (!Number.isNaN(value.getTime())) createdAt.$gte = value; }
    if (query.to) { const value = new Date(query.to); if (!Number.isNaN(value.getTime())) createdAt.$lte = value; }
    if (Object.keys(createdAt).length) filter.createdAt = createdAt;
    if (actor.role === EventMemberRole.RETOUCHER) filter.assignedRetoucherId = this.oid(String(userId));
    const limit = Math.min(Math.max(Number(query.limit) || 250, 1), 1000);
    const [data, counts] = await Promise.all([
      this.jobs.find(filter)
        .populate('eventImageId', 'imageUrl isPublished createdAt mediaType')
        .populate('albumId', 'title')
        .populate('photographerId', 'name email profileImage')
        .populate('assignedRetoucherId', 'name email profileImage')
        .populate('reviewedBy', 'name email')
        .populate('outputEventImageId', 'imageUrl isPublished')
        .sort({ createdAt: -1 }).limit(limit).lean(),
      this.jobs.aggregate<{ _id: string; count: number }>([
        { $match: { eventId: this.oid(query.eventId), ...(actor.role === EventMemberRole.RETOUCHER ? { assignedRetoucherId: this.oid(String(userId)) } : {}) } },
        { $group: { _id: '$status', count: { $sum: 1 } } },
      ]),
    ]);
    return { data, totalItems: counts.reduce((n, x) => n + x.count, 0), summary: Object.fromEntries(counts.map((x) => [x._id, x.count])) };
  }

  async assign(dto: AssignRetouchDto, userId?: string, globalRole?: string) {
    await this.assertManager(dto.eventId, userId, globalRole);
    const retoucher = await this.membersModel.findOne({ eventId: this.oid(dto.eventId), userId: this.oid(dto.retoucherId), role: EventMemberRole.RETOUCHER, status: EventMemberStatus.ACTIVE }).select('_id').lean();
    if (!retoucher) throw new HttpException('Active event retoucher not found', 400);
    const ids = [...new Set(dto.jobIds)].map((id) => this.oid(id));
    const result = await this.jobs.updateMany({ _id: { $in: ids }, eventId: this.oid(dto.eventId) }, { $set: { assignedRetoucherId: this.oid(dto.retoucherId), assignedAt: new Date(), status: RetouchJobStatus.ASSIGNED, ...(dto.note ? { internalNote: dto.note } : {}) } });
    this.emit(dto.eventId, 'retouch.assigned', { jobIds: dto.jobIds, retoucherId: dto.retoucherId });
    return { message: 'Retouch jobs assigned', updated: result.modifiedCount };
  }

  async unassign(eventId: string, jobIds: string[], userId?: string, globalRole?: string) {
    await this.assertManager(eventId, userId, globalRole);
    const ids = [...new Set(jobIds)].filter(Types.ObjectId.isValid).map((id) => this.oid(id));
    const result = await this.jobs.updateMany({ _id: { $in: ids }, eventId: this.oid(eventId) }, { $set: { status: RetouchJobStatus.INCOMING }, $unset: { assignedRetoucherId: '', assignedAt: '' } });
    this.emit(eventId, 'retouch.unassigned', { jobIds });
    return { message: 'Retouch jobs unassigned', updated: result.modifiedCount };
  }

  private async jobForActor(jobId: string, userId?: string, globalRole?: string, mode: 'retouch' | 'review' = 'retouch') {
    const job = await this.jobs.findById(jobId).exec();
    if (!job) throw new HttpException('Retouch job not found', 404);
    const actor = mode === 'review' ? await this.assertReviewer(String(job.eventId), userId, globalRole) : await this.assertRetoucher(String(job.eventId), userId, globalRole);
    if (actor.role === EventMemberRole.RETOUCHER && String(job.assignedRetoucherId || '') !== userId) throw new ForbiddenException('This retouch job is not assigned to you');
    return { job, actor };
  }

  async updateStatus(dto: RetouchStatusDto, userId?: string, globalRole?: string) {
    const { job } = await this.jobForActor(dto.jobId, userId, globalRole);
    const allowed = [RetouchJobStatus.DOWNLOADED, RetouchJobStatus.RETOUCHING, RetouchJobStatus.FAILED];
    if (!allowed.includes(dto.status)) throw new HttpException('Use retouch upload/review endpoints for this status', 400);
    const now = new Date();
    const set: Record<string, unknown> = { status: dto.status, ...(dto.note ? { internalNote: dto.note } : {}), ...(dto.deviceId ? { desktopDeviceId: dto.deviceId, desktopLastSeenAt: now } : {}) };
    if (dto.status === RetouchJobStatus.DOWNLOADED) set.downloadedAt = now;
    if (dto.status === RetouchJobStatus.RETOUCHING) set.retouchStartedAt = now;
    const data = await this.jobs.findByIdAndUpdate(job._id, { $set: set }, { new: true }).lean();
    this.emit(String(job.eventId), 'retouch.status', data);
    void this.webhooks.publish(String(job.eventId), 'retouch.status', { jobId: String(job._id), status: dto.status });
    return { message: 'Retouch status updated', data };
  }

  private async workflowSettings(eventId: string) {
    return this.settingsModel.findOneAndUpdate({ eventId: this.oid(eventId) }, { $setOnInsert: { eventId: this.oid(eventId), bypassReviewer: false, autoPublishApproved: true, desktopDownloadConcurrency: 3 } }, { upsert: true, new: true, setDefaultsOnInsert: true }).lean();
  }

  async uploadVersion(dto: RetouchVersionDto, userId?: string, globalRole?: string) {
    const { job } = await this.jobForActor(dto.jobId, userId, globalRole);
    const eventId = String(job.eventId);
    const original = await this.images.findById(job.eventImageId).lean();
    if (!original) throw new HttpException('Original photo not found', 404);
    const latest = await this.versionsModel.findOne({ eventImageId: job.eventImageId }).sort({ version: -1 }).select('version').lean();
    const version = (latest?.version || 1) + 1;
    const output = await this.images.create({
      eventId: job.eventId, imageUrl: dto.imageUrl, userTakenBy: original.userTakenBy,
      albumId: original.albumId, isEnhanced: true, enhancedFromId: original._id,
      isPublished: false, mediaType: original.mediaType || 'photo', aiReviewStatus: 'approved',
    });
    await this.versionsModel.create({ eventId: job.eventId, eventImageId: job.eventImageId, retouchJobId: job._id, createdBy: userId ? this.oid(userId) : undefined, version, type: 'retouched', imageUrl: dto.imageUrl, checksum: dto.checksum, note: dto.note });
    const settings = await this.workflowSettings(eventId);
    const autoApprove = settings?.bypassReviewer === true;
    const now = new Date();
    const data = await this.jobs.findByIdAndUpdate(job._id, { $set: {
      currentImageUrl: dto.imageUrl, retouchedImageUrl: dto.imageUrl, checksum: dto.checksum,
      outputEventImageId: output._id, status: autoApprove ? RetouchJobStatus.APPROVED : RetouchJobStatus.READY_FOR_REVIEW,
      readyForReviewAt: now, ...(dto.note ? { internalNote: dto.note } : {}),
      ...(dto.deviceId ? { desktopDeviceId: dto.deviceId, desktopLastSeenAt: now } : {}),
      ...(autoApprove ? { reviewedAt: now, reviewedBy: userId ? this.oid(userId) : undefined } : {}),
    } }, { new: true }).lean();
    if (autoApprove && settings?.autoPublishApproved !== false) await this.publishApproved(String(job._id));
    this.emit(eventId, 'retouch.version', data);
    void this.webhooks.publish(eventId, 'retouch.ready', { jobId: String(job._id), outputEventImageId: String(output._id), status: data?.status });
    return { message: autoApprove ? 'Retouched version approved by event workflow' : 'Retouched version ready for review', data, version, outputEventImageId: String(output._id) };
  }

  private async publishApproved(jobId: string) {
    const job = await this.jobs.findById(jobId).exec();
    if (!job?.outputEventImageId) return null;
    await Promise.all([
      this.images.updateOne({ _id: job.eventImageId }, { $set: { isPublished: false } }),
      this.images.updateOne({ _id: job.outputEventImageId }, { $set: { isPublished: true } }),
      this.transfers.markPublication(String(job.eventId), String(job.eventImageId), false),
    ]);
    job.status = RetouchJobStatus.PUBLISHED;
    job.publishedAt = new Date();
    await job.save();
    void this.webhooks.publish(String(job.eventId), 'retouch.published', {
      jobId: String(job._id),
      sourceEventImageId: String(job.eventImageId),
      outputEventImageId: String(job.outputEventImageId),
      status: 'published',
    });
    void this.webhooks.publish(String(job.eventId), 'photo.status', {
      imageId: String(job.outputEventImageId),
      status: 'published',
      isPublished: true,
    });
    return job;
  }

  async review(dto: ReviewRetouchDto, userId?: string, globalRole?: string) {
    const { job } = await this.jobForActor(dto.jobId, userId, globalRole, 'review');
    if (![RetouchJobStatus.READY_FOR_REVIEW, RetouchJobStatus.APPROVED, RetouchJobStatus.REJECTED].includes(job.status)) throw new HttpException('Job is not ready for review', 400);
    const approved = dto.decision === 'approve';
    const data = await this.jobs.findByIdAndUpdate(job._id, { $set: { status: approved ? RetouchJobStatus.APPROVED : RetouchJobStatus.REJECTED, reviewedBy: this.oid(String(userId)), reviewedAt: new Date(), rejectionReason: approved ? undefined : dto.reason } }, { new: true }).lean();
    const settings = await this.workflowSettings(String(job.eventId));
    if (approved && dto.publish !== false && settings?.autoPublishApproved !== false) await this.publishApproved(String(job._id));
    this.emit(String(job.eventId), approved ? 'retouch.approved' : 'retouch.rejected', data);
    return { message: approved ? 'Retouch approved' : 'Retouch rejected', data: await this.jobs.findById(job._id).lean() };
  }

  async bulkReview(dto: BulkReviewRetouchDto, userId?: string, globalRole?: string) {
    const results = await Promise.allSettled(dto.jobIds.map((jobId) => this.review({ jobId, decision: dto.decision, reason: dto.reason, publish: dto.publish }, userId, globalRole)));
    return { total: dto.jobIds.length, completed: results.filter((x) => x.status === 'fulfilled').length, failed: results.filter((x) => x.status === 'rejected').length };
  }

  async versions(jobId: string, userId?: string, globalRole?: string) {
    const job = await this.jobs.findById(jobId).select('eventId eventImageId').lean();
    if (!job) throw new HttpException('Retouch job not found', 404);
    await this.members.assertCanAccess(String(job.eventId), userId, globalRole);
    const data = await this.versionsModel.find({ eventImageId: job.eventImageId }).populate('createdBy', 'name email').sort({ version: 1 }).lean();
    return { data, totalItems: data.length };
  }

  async getSettings(eventId: string, userId?: string, globalRole?: string) {
    await this.assertManager(eventId, userId, globalRole);
    return { data: await this.workflowSettings(eventId) };
  }
  async updateSettings(dto: RetouchSettingsDto, userId?: string, globalRole?: string) {
    await this.assertManager(dto.eventId, userId, globalRole);
    const set: Record<string, unknown> = {};
    if (dto.bypassReviewer !== undefined) set.bypassReviewer = dto.bypassReviewer;
    if (dto.autoPublishApproved !== undefined) set.autoPublishApproved = dto.autoPublishApproved;
    if (dto.desktopDownloadConcurrency !== undefined) set.desktopDownloadConcurrency = dto.desktopDownloadConcurrency;
    const data = await this.settingsModel.findOneAndUpdate({ eventId: this.oid(dto.eventId) }, { $set: set, $setOnInsert: { eventId: this.oid(dto.eventId) } }, { upsert: true, new: true, setDefaultsOnInsert: true }).lean();
    return { message: 'Retouch workflow settings updated', data };
  }

  async desktopFeed(query: DesktopFeedDto, userId?: string, globalRole?: string) {
    const actor = await this.assertRetoucher(query.eventId, userId, globalRole);
    const filter: Record<string, unknown> = { eventId: this.oid(query.eventId), status: { $in: [RetouchJobStatus.ASSIGNED, RetouchJobStatus.REJECTED, RetouchJobStatus.FAILED] } };
    if (actor.role === EventMemberRole.RETOUCHER) filter.assignedRetoucherId = this.oid(String(userId));
    if (query.albumId) filter.albumId = this.oid(query.albumId);
    const data = await this.jobs.find(filter).populate('albumId', 'title').populate('photographerId', 'name').sort({ createdAt: 1 }).limit(query.limit || 100).lean();
    const settings = await this.workflowSettings(query.eventId);
    return { data, totalItems: data.length, downloadConcurrency: settings?.desktopDownloadConcurrency || 3 };
  }

  async desktopStatus(eventId: string, userId?: string, globalRole?: string) {
    await this.assertManager(eventId, userId, globalRole);
    const rows = await this.jobs.aggregate<{
      _id: { deviceId: string; retoucherId?: Types.ObjectId };
      lastSeenAt?: Date;
      totalJobs: number;
      downloaded: number;
      retouching: number;
      readyForReview: number;
      published: number;
    }>([
      { $match: { eventId: this.oid(eventId), desktopDeviceId: { $type: 'string', $ne: '' } } },
      { $group: {
        _id: { deviceId: '$desktopDeviceId', retoucherId: '$assignedRetoucherId' },
        lastSeenAt: { $max: '$desktopLastSeenAt' },
        totalJobs: { $sum: 1 },
        downloaded: { $sum: { $cond: [{ $eq: ['$status', RetouchJobStatus.DOWNLOADED] }, 1, 0] } },
        retouching: { $sum: { $cond: [{ $eq: ['$status', RetouchJobStatus.RETOUCHING] }, 1, 0] } },
        readyForReview: { $sum: { $cond: [{ $eq: ['$status', RetouchJobStatus.READY_FOR_REVIEW] }, 1, 0] } },
        published: { $sum: { $cond: [{ $eq: ['$status', RetouchJobStatus.PUBLISHED] }, 1, 0] } },
      } },
      { $sort: { lastSeenAt: -1 } },
      { $limit: 100 },
    ]);
    const onlineCutoff = Date.now() - 45_000;
    const data = rows.map((row) => ({
      deviceId: row._id.deviceId,
      retoucherId: row._id.retoucherId ? String(row._id.retoucherId) : undefined,
      lastSeenAt: row.lastSeenAt,
      online: Boolean(row.lastSeenAt && new Date(row.lastSeenAt).getTime() >= onlineCutoff),
      totalJobs: row.totalJobs,
      downloaded: row.downloaded,
      retouching: row.retouching,
      readyForReview: row.readyForReview,
      published: row.published,
    }));
    return { data, totalItems: data.length, online: data.filter((row) => row.online).length };
  }
  async heartbeat(eventId: string, deviceId: string, userId?: string, globalRole?: string) {
    const actor = await this.assertRetoucher(eventId, userId, globalRole);
    const filter: Record<string, unknown> = { eventId: this.oid(eventId), ...(actor.role === EventMemberRole.RETOUCHER ? { assignedRetoucherId: this.oid(String(userId)) } : {}) };
    await this.jobs.updateMany(filter, { $set: { desktopDeviceId: deviceId, desktopLastSeenAt: new Date() } });
    return { ok: true, at: new Date().toISOString() };
  }

  async stream(eventId: string, userId?: string, globalRole?: string): Promise<Observable<MessageEvent>> {
    await this.members.assertCanAccess(eventId, userId, globalRole);
    return merge(
      this.subject(eventId).asObservable().pipe(map((data) => ({ type: 'retouch', data }) as MessageEvent)),
      interval(15000).pipe(map(() => ({ type: 'heartbeat', data: { at: new Date().toISOString() } }) as MessageEvent)),
    );
  }
}
