import {
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { Model, Types } from 'mongoose';
import { randomBytes } from 'crypto';
import { Event, EventDocument } from '../event/entities/event.entity';
import {
  EventInvitation,
  EventInvitationDocument,
  EventInvitationStatus,
} from '../event/entities/event-invitation.entity';
import { User, UserDocument, UserType } from '../user/entities/user.entity';
import { Album, AlbumDocument } from '../album/entities/album.entity';
import {
  SubscriptionPlan,
  SubscriptionPlanDocument,
} from '../subscription/entities/subscription-plan.entity';
import {
  AddEventMemberDto,
  UpdateEventMemberDto,
} from './dto/event-member.dto';
import {
  EventMember,
  EventMemberDocument,
  EventMemberRole,
  EventMemberStatus,
} from './entities/event-member.entity';

@Injectable()
export class EventMemberService {
  constructor(
    @InjectModel(EventMember.name)
    private readonly memberModel: Model<EventMemberDocument>,
    @InjectModel(Event.name)
    private readonly eventModel: Model<EventDocument>,
    @InjectModel(User.name)
    private readonly userModel: Model<UserDocument>,
    @InjectModel(EventInvitation.name)
    private readonly invitationModel: Model<EventInvitationDocument>,
    @InjectModel(Album.name)
    private readonly albumModel: Model<AlbumDocument>,
    @InjectModel(SubscriptionPlan.name)
    private readonly subscriptionPlanModel: Model<SubscriptionPlanDocument>,
  ) {}

  private toObjectId(id: string | Types.ObjectId) {
    return new Types.ObjectId(String(id));
  }

  private async assertAlbumsBelongToEvent(
    eventId: string,
    albumIds: string[] = [],
  ) {
    const uniqueIds = [...new Set(albumIds)];
    if (!uniqueIds.length) return;
    if (
      !Types.ObjectId.isValid(eventId) ||
      uniqueIds.some((id) => !Types.ObjectId.isValid(id))
    ) {
      throw new ForbiddenException('Invalid event category assignment');
    }
    const count = await this.albumModel.countDocuments({
      _id: { $in: uniqueIds.map((id) => this.toObjectId(id)) },
      eventId: this.toObjectId(eventId),
    });
    if (count !== uniqueIds.length) {
      throw new ForbiddenException(
        'Every assigned category must belong to this event',
      );
    }
  }

  private async hasPlannerSubscription(userId: string) {
    const user = await this.userModel
      .findById(userId)
      .select('role isSubscriber subscriptionPlanId subscriptionEndDate')
      .lean();
    if (!user) return false;
    if (
      user.role === UserType.ADMIN ||
      user.role === UserType.USER ||
      user.role === UserType.EVENT_PLANNER ||
      user.role === UserType.EDITOR
    ) {
      return true;
    }
    if (
      user.role !== UserType.PHOTOGRAPHER ||
      !user.isSubscriber ||
      !user.subscriptionPlanId
    ) {
      return false;
    }
    if (
      user.subscriptionEndDate &&
      new Date(user.subscriptionEndDate).getTime() < Date.now()
    ) {
      return false;
    }
    const plan = await this.subscriptionPlanModel
      .findById(user.subscriptionPlanId)
      .select('features isActive')
      .lean();
    return Boolean(
      plan?.isActive !== false &&
      (plan?.features || []).includes('event.create'),
    );
  }

  async assertCanCreateOwnEvent(userId?: string, globalRole?: string) {
    if (!userId || !Types.ObjectId.isValid(userId)) {
      throw new ForbiddenException('Login required to create events');
    }
    if (
      globalRole === UserType.ADMIN ||
      globalRole === UserType.USER ||
      globalRole === UserType.EVENT_PLANNER ||
      globalRole === UserType.EDITOR
    ) {
      return true;
    }
    if (
      globalRole === UserType.PHOTOGRAPHER &&
      (await this.hasPlannerSubscription(userId))
    ) {
      return true;
    }
    throw new ForbiddenException(
      'Your photographer account needs a planner-enabled plan to create solo events',
    );
  }

  async workspaceAccess(userId?: string, globalRole?: string) {
    if (!userId || !Types.ObjectId.isValid(userId)) {
      return { planner: false, photographer: false, roles: [] as string[] };
    }
    const roles = await this.memberModel.distinct('role', {
      userId: this.toObjectId(userId),
      status: EventMemberStatus.ACTIVE,
    });
    const roleSet = new Set(roles.map(String));
    const plannerSubscription =
      globalRole === UserType.PHOTOGRAPHER
        ? await this.hasPlannerSubscription(userId)
        : false;
    const planner =
      globalRole === UserType.USER ||
      globalRole === UserType.EVENT_PLANNER ||
      globalRole === UserType.EDITOR ||
      plannerSubscription ||
      roleSet.has(EventMemberRole.OWNER) ||
      roleSet.has(EventMemberRole.EVENT_PLANNER);
    const photographer =
      globalRole === UserType.PHOTOGRAPHER ||
      roleSet.has(EventMemberRole.PHOTOGRAPHER) ||
      roleSet.has(EventMemberRole.ASSISTANT_PHOTOGRAPHER);
    const retoucher =
      planner ||
      roleSet.has(EventMemberRole.RETOUCHER) ||
      roleSet.has(EventMemberRole.REVIEWER);
    const reviewer = planner || roleSet.has(EventMemberRole.REVIEWER);
    return { planner, photographer, retoucher, reviewer, roles: [...roleSet] };
  }

  async allowedAlbumIds(
    eventId: string,
    userId?: string,
    globalRole?: string,
  ): Promise<string[] | null> {
    const event = await this.eventOrThrow(eventId);
    if (!userId || !Types.ObjectId.isValid(userId)) {
      throw new ForbiddenException('Event access denied');
    }
    if (globalRole === UserType.ADMIN || String(event.userId) === userId) {
      return null;
    }

    const memberships = await this.memberModel
      .find({
        eventId: this.toObjectId(eventId),
        userId: this.toObjectId(userId),
        status: EventMemberStatus.ACTIVE,
      })
      .select('role assignedAlbumIds')
      .lean();

    if (!memberships.length) return null;
    if (
      memberships.some(
        (member) =>
          member.role !== EventMemberRole.PHOTOGRAPHER &&
          member.role !== EventMemberRole.ASSISTANT_PHOTOGRAPHER,
      )
    ) {
      return null;
    }

    if (
      memberships.some((member) => (member.assignedAlbumIds || []).length === 0)
    ) {
      return null;
    }

    return [
      ...new Set(
        memberships.flatMap((member) =>
          (member.assignedAlbumIds || []).map(String),
        ),
      ),
    ];
  }

  private createJoinCode() {
    return randomBytes(5).toString('hex').toUpperCase();
  }

  async getOrCreateJoinCode(
    eventId: string,
    actorId?: string,
    actorRole?: string,
    rotate = false,
  ) {
    await this.assertCanManage(eventId, actorId, actorRole);
    const current = await this.eventModel
      .findById(eventId)
      .select('joinCode title')
      .lean();
    if (!current) throw new NotFoundException('Event not found');
    if (current.joinCode && !rotate) {
      return { code: current.joinCode, eventId, title: current.title };
    }

    for (let attempt = 0; attempt < 5; attempt += 1) {
      const code = this.createJoinCode();
      try {
        const updated = await this.eventModel
          .findByIdAndUpdate(
            eventId,
            { $set: { joinCode: code } },
            { new: true },
          )
          .select('joinCode title')
          .lean();
        if (!updated) throw new NotFoundException('Event not found');
        return { code: updated.joinCode, eventId, title: updated.title };
      } catch (error) {
        if ((error as { code?: number }).code !== 11000 || attempt === 4) {
          throw error;
        }
      }
    }
    throw new ForbiddenException('Could not create event join code');
  }

  async joinByCode(code: string, userId?: string) {
    if (!userId || !Types.ObjectId.isValid(userId)) {
      throw new ForbiddenException('Login required to join event');
    }
    const normalized = code.trim().toUpperCase();
    const [event, user] = await Promise.all([
      this.eventModel
        .findOne({ joinCode: normalized, isActive: true })
        .select('userId title')
        .lean(),
      this.userModel.findById(userId).select('isActive').lean(),
    ]);
    if (!event)
      throw new NotFoundException('Invalid or inactive event join code');
    if (!user?.isActive)
      throw new ForbiddenException('Active account required');

    const member = await this.memberModel
      .findOneAndUpdate(
        {
          eventId: event._id,
          userId: this.toObjectId(userId),
          role: EventMemberRole.PHOTOGRAPHER,
        },
        {
          $setOnInsert: {
            invitedBy: event.userId,
            assignedAlbumIds: [],
            canPublish: true,
          },
          $set: {
            status: EventMemberStatus.ACTIVE,
            respondedAt: new Date(),
          },
        },
        { upsert: true, new: true, setDefaultsOnInsert: true },
      )
      .populate('eventId', 'title description image isActive isPublished')
      .populate('assignedAlbumIds', 'title description')
      .lean();

    return {
      message: 'Joined event as photographer',
      data: member,
    };
  }
  async ensureOwnerMembership(eventId: string, ownerId: string) {
    if (!Types.ObjectId.isValid(eventId) || !Types.ObjectId.isValid(ownerId))
      return;
    await this.memberModel.updateOne(
      {
        eventId: this.toObjectId(eventId),
        userId: this.toObjectId(ownerId),
        role: EventMemberRole.OWNER,
      },
      {
        $setOnInsert: {
          invitedBy: this.toObjectId(ownerId),
          assignedAlbumIds: [],
          canPublish: true,
        },
        $set: { status: EventMemberStatus.ACTIVE },
      },
      { upsert: true },
    );
  }

  private async eventOrThrow(eventId: string) {
    if (!Types.ObjectId.isValid(eventId))
      throw new NotFoundException('Event not found');
    const event = await this.eventModel
      .findById(eventId)
      .select('userId title')
      .lean();
    if (!event) throw new NotFoundException('Event not found');
    return event;
  }

  async assertCanAccess(eventId: string, userId?: string, globalRole?: string) {
    const event = await this.eventOrThrow(eventId);
    if (!userId || !Types.ObjectId.isValid(userId)) {
      throw new ForbiddenException('Event access denied');
    }
    if (globalRole === UserType.ADMIN || String(event.userId) === userId) {
      await this.ensureOwnerMembership(eventId, String(event.userId));
      return event;
    }

    const [member, legacyInvite] = await Promise.all([
      this.memberModel
        .findOne({
          eventId: this.toObjectId(eventId),
          userId: this.toObjectId(userId),
          status: EventMemberStatus.ACTIVE,
        })
        .select('_id role canPublish assignedAlbumIds')
        .lean(),
      this.invitationModel
        .findOne({
          eventId: this.toObjectId(eventId),
          photographerId: this.toObjectId(userId),
          status: EventInvitationStatus.ACCEPTED,
        })
        .select('_id')
        .lean(),
    ]);

    if (!member && !legacyInvite)
      throw new ForbiddenException('Event access denied');
    return event;
  }

  async assertCanUpload(
    eventId: string,
    userId?: string,
    globalRole?: string,
    albumId?: string,
  ) {
    const event = await this.eventOrThrow(eventId);
    if (!userId || !Types.ObjectId.isValid(userId)) {
      throw new ForbiddenException('Event upload denied');
    }
    if (globalRole === UserType.ADMIN || String(event.userId) === userId) {
      return event;
    }

    const memberships = await this.memberModel
      .find({
        eventId: this.toObjectId(eventId),
        userId: this.toObjectId(userId),
        status: EventMemberStatus.ACTIVE,
        role: {
          $in: [
            EventMemberRole.PHOTOGRAPHER,
            EventMemberRole.ASSISTANT_PHOTOGRAPHER,
            EventMemberRole.EVENT_PLANNER,
          ],
        },
      })
      .select('assignedAlbumIds role')
      .lean();

    if (memberships.length) {
      if (
        memberships.some(
          (member) => member.role === EventMemberRole.EVENT_PLANNER,
        )
      ) {
        return event;
      }

      const unrestricted = memberships.some(
        (member) => (member.assignedAlbumIds || []).length === 0,
      );
      if (unrestricted) return event;

      const assigned = new Set(
        memberships.flatMap((member) =>
          (member.assignedAlbumIds || []).map(String),
        ),
      );
      if (!albumId || !assigned.has(albumId)) {
        throw new ForbiddenException(
          'This photographer is not assigned to that category',
        );
      }
      return event;
    }

    const legacyInvite = await this.invitationModel
      .findOne({
        eventId: this.toObjectId(eventId),
        photographerId: this.toObjectId(userId),
        status: EventInvitationStatus.ACCEPTED,
      })
      .select('_id')
      .lean();
    if (!legacyInvite) throw new ForbiddenException('Event upload denied');
    return event;
  }

  async assertCanPublish(
    eventId: string,
    userId?: string,
    globalRole?: string,
  ) {
    const event = await this.eventOrThrow(eventId);
    if (globalRole === UserType.ADMIN || String(event.userId) === userId) {
      return event;
    }
    if (!userId || !Types.ObjectId.isValid(userId)) {
      throw new ForbiddenException('Event publish denied');
    }

    const member = await this.memberModel
      .findOne({
        eventId: this.toObjectId(eventId),
        userId: this.toObjectId(userId),
        status: EventMemberStatus.ACTIVE,
        $or: [
          { role: EventMemberRole.EVENT_PLANNER },
          { role: EventMemberRole.REVIEWER },
          { canPublish: true },
        ],
      })
      .select('_id')
      .lean();
    if (member) return event;

    const legacyInvite = await this.invitationModel
      .findOne({
        eventId: this.toObjectId(eventId),
        photographerId: this.toObjectId(userId),
        status: EventInvitationStatus.ACCEPTED,
      })
      .select('_id')
      .lean();
    if (!legacyInvite) throw new ForbiddenException('Event publish denied');
    return event;
  }

  async assertCanManage(eventId: string, userId?: string, globalRole?: string) {
    const event = await this.eventOrThrow(eventId);
    if (globalRole === UserType.ADMIN || String(event.userId) === userId)
      return event;

    if (!userId || !Types.ObjectId.isValid(userId)) {
      throw new ForbiddenException('Only event owner/planner can manage team');
    }
    const planner = await this.memberModel
      .findOne({
        eventId: this.toObjectId(eventId),
        userId: this.toObjectId(userId),
        role: EventMemberRole.EVENT_PLANNER,
        status: EventMemberStatus.ACTIVE,
      })
      .select('_id')
      .lean();
    if (!planner)
      throw new ForbiddenException('Only event owner/planner can manage team');
    return event;
  }

  async add(dto: AddEventMemberDto, actorId?: string, actorRole?: string) {
    const event = await this.assertCanManage(dto.eventId, actorId, actorRole);
    await this.assertAlbumsBelongToEvent(dto.eventId, dto.assignedAlbumIds);
    if (dto.role === EventMemberRole.OWNER) {
      throw new ForbiddenException(
        'Event owner cannot be replaced from team management',
      );
    }
    const user = await this.userModel
      .findById(dto.userId)
      .select('name email phone userId role isActive')
      .lean();
    if (!user?.isActive) throw new NotFoundException('Active user not found');

    const existingMember = await this.memberModel
      .findOne({
        eventId: this.toObjectId(dto.eventId),
        userId: this.toObjectId(dto.userId),
        role: dto.role,
      })
      .select('status')
      .lean();
    const nextStatus =
      existingMember?.status === EventMemberStatus.ACTIVE
        ? EventMemberStatus.ACTIVE
        : EventMemberStatus.PENDING;

    const member = await this.memberModel
      .findOneAndUpdate(
        {
          eventId: this.toObjectId(dto.eventId),
          userId: this.toObjectId(dto.userId),
          role: dto.role,
        },
        {
          $set: {
            invitedBy: this.toObjectId(actorId || String(event.userId)),
            assignedAlbumIds: (dto.assignedAlbumIds || []).map((id) =>
              this.toObjectId(id),
            ),
            canPublish: dto.canPublish ?? dto.role.includes('photographer'),
            status: nextStatus,
          },
        },
        { upsert: true, new: true, setDefaultsOnInsert: true },
      )
      .populate('userId', 'name email phone userId role')
      .lean();

    return { message: 'Team member invited', data: member };
  }

  async list(eventId: string, actorId?: string, actorRole?: string) {
    await this.assertCanManage(eventId, actorId, actorRole);
    const data = await this.memberModel
      .find({ eventId: this.toObjectId(eventId) })
      .populate('userId', 'name email phone userId role profileImage')
      .populate('assignedAlbumIds', 'title')
      .sort({ createdAt: 1 })
      .lean();
    return { data, totalItems: data.length };
  }

  async photographerSummaryByEventIds(eventIds: Types.ObjectId[]) {
    if (!eventIds.length) {
      return new Map<
        string,
        {
          totalInvited: number;
          pendingInvites: number;
          acceptedInvites: number;
        }
      >();
    }

    const rows = await this.memberModel.aggregate<{
      _id: Types.ObjectId;
      totalInvited: number;
      pendingInvites: number;
      acceptedInvites: number;
    }>([
      {
        $match: {
          eventId: { $in: eventIds },
          role: {
            $in: [
              EventMemberRole.PHOTOGRAPHER,
              EventMemberRole.ASSISTANT_PHOTOGRAPHER,
            ],
          },
          status: {
            $in: [EventMemberStatus.PENDING, EventMemberStatus.ACTIVE],
          },
        },
      },
      {
        $group: {
          _id: '$eventId',
          totalInvited: { $sum: 1 },
          pendingInvites: {
            $sum: {
              $cond: [{ $eq: ['$status', EventMemberStatus.PENDING] }, 1, 0],
            },
          },
          acceptedInvites: {
            $sum: {
              $cond: [{ $eq: ['$status', EventMemberStatus.ACTIVE] }, 1, 0],
            },
          },
        },
      },
    ]);

    return new Map(
      rows.map((row) => [
        String(row._id),
        {
          totalInvited: row.totalInvited,
          pendingInvites: row.pendingInvites,
          acceptedInvites: row.acceptedInvites,
        },
      ]),
    );
  }
  async activeEventIds(userId?: string, roles?: EventMemberRole[]) {
    if (!userId || !Types.ObjectId.isValid(userId))
      return [] as Types.ObjectId[];
    return this.memberModel.distinct('eventId', {
      userId: this.toObjectId(userId),
      status: EventMemberStatus.ACTIVE,
      ...(roles?.length ? { role: { $in: roles } } : {}),
    });
  }
  async myMemberships(userId?: string) {
    if (!userId || !Types.ObjectId.isValid(userId))
      return { data: [], totalItems: 0 };
    const data = await this.memberModel
      .find({
        userId: this.toObjectId(userId),
        status: { $in: [EventMemberStatus.PENDING, EventMemberStatus.ACTIVE] },
      })
      .populate('eventId', 'title description image isActive isPublished')
      .populate('invitedBy', 'name email')
      .populate('assignedAlbumIds', 'title description')
      .sort({ createdAt: -1 })
      .lean();
    return { data, totalItems: data.length };
  }

  async accept(memberId: string, userId?: string) {
    if (!userId || !Types.ObjectId.isValid(memberId))
      throw new ForbiddenException('Invalid membership');
    const member = await this.memberModel
      .findOneAndUpdate(
        {
          _id: memberId,
          userId: this.toObjectId(userId),
          status: EventMemberStatus.PENDING,
        },
        { $set: { status: EventMemberStatus.ACTIVE, respondedAt: new Date() } },
        { new: true },
      )
      .lean();
    if (!member) throw new NotFoundException('Pending membership not found');
    return { message: 'Team invitation accepted', data: member };
  }

  async update(
    memberId: string,
    dto: UpdateEventMemberDto,
    actorId?: string,
    actorRole?: string,
  ) {
    if (!Types.ObjectId.isValid(memberId))
      throw new NotFoundException('Member not found');
    const existing = await this.memberModel
      .findById(memberId)
      .select('eventId role')
      .lean();
    if (!existing) throw new NotFoundException('Member not found');
    await this.assertCanManage(String(existing.eventId), actorId, actorRole);
    if (dto.assignedAlbumIds) {
      await this.assertAlbumsBelongToEvent(
        String(existing.eventId),
        dto.assignedAlbumIds,
      );
    }
    if (
      existing.role === EventMemberRole.OWNER ||
      dto.role === EventMemberRole.OWNER
    ) {
      throw new ForbiddenException('Owner membership cannot be changed');
    }
    const update: Record<string, unknown> = {};
    if (dto.role) update.role = dto.role;
    if (dto.assignedAlbumIds)
      update.assignedAlbumIds = dto.assignedAlbumIds.map((id) =>
        this.toObjectId(id),
      );
    if (dto.canPublish !== undefined) update.canPublish = dto.canPublish;
    const member = await this.memberModel
      .findByIdAndUpdate(memberId, { $set: update }, { new: true })
      .populate('userId', 'name email phone userId role')
      .lean();
    return { message: 'Team member updated', data: member };
  }

  async leave(memberId: string, userId?: string) {
    if (
      !userId ||
      !Types.ObjectId.isValid(userId) ||
      !Types.ObjectId.isValid(memberId)
    ) {
      throw new NotFoundException('Membership not found');
    }
    const existing = await this.memberModel
      .findOne({ _id: memberId, userId: this.toObjectId(userId) })
      .select('role')
      .lean();
    if (!existing) throw new NotFoundException('Membership not found');
    if (existing.role === EventMemberRole.OWNER) {
      throw new ForbiddenException('Event owner cannot leave their own event');
    }
    await this.memberModel.deleteOne({ _id: memberId });
    return { message: 'Event membership removed' };
  }
  async remove(memberId: string, actorId?: string, actorRole?: string) {
    if (!Types.ObjectId.isValid(memberId))
      throw new NotFoundException('Member not found');
    const existing = await this.memberModel
      .findById(memberId)
      .select('eventId role')
      .lean();
    if (!existing) throw new NotFoundException('Member not found');
    await this.assertCanManage(String(existing.eventId), actorId, actorRole);
    if (existing.role === EventMemberRole.OWNER)
      throw new ForbiddenException('Owner cannot be removed');
    await this.memberModel.deleteOne({ _id: memberId });
    return { message: 'Team member removed' };
  }

  async activateLegacyPhotographer(
    eventId: string,
    photographerId: string,
    inviterId: string,
  ) {
    if (![eventId, photographerId, inviterId].every(Types.ObjectId.isValid))
      return;
    await this.memberModel.updateOne(
      {
        eventId: this.toObjectId(eventId),
        userId: this.toObjectId(photographerId),
        role: EventMemberRole.PHOTOGRAPHER,
      },
      {
        $set: {
          status: EventMemberStatus.ACTIVE,
          respondedAt: new Date(),
          canPublish: true,
          invitedBy: this.toObjectId(inviterId),
        },
        $setOnInsert: { assignedAlbumIds: [] },
      },
      { upsert: true },
    );
  }
}

