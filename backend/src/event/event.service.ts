import { HttpException, Injectable, Logger } from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { Event, EventDocument } from './entities/event.entity';
import { Model, Types } from 'mongoose';
import {
  CreateEventDto,
  UpdateEventDto,
  EventFilterDto,
} from './dto/create-event.dto';
import {
  EventInvitation,
  EventInvitationDocument,
  EventInvitationStatus,
} from './entities/event-invitation.entity';
import { InvitePhotographerDto } from './dto/event-invitation.dto';
import { EventMemberService } from '../event-member/event-member.service';
import { EventMemberRole } from '../event-member/entities/event-member.entity';
import { User, UserDocument, UserType } from '../user/entities/user.entity';
import {
  SubscriptionPlan,
  SubscriptionPlanDocument,
} from '../subscription/entities/subscription-plan.entity';
import {
  EventImage,
  EventImageDocument,
} from '../event-image/entities/event-image.entity';

@Injectable()
export class EventService {
  private logger = new Logger(EventService.name);

  constructor(
    @InjectModel(Event.name)
    private eventModel: Model<EventDocument>,
    @InjectModel(EventInvitation.name)
    private eventInvitationModel: Model<EventInvitationDocument>,
    @InjectModel(User.name)
    private userModel: Model<UserDocument>,
    @InjectModel(SubscriptionPlan.name)
    private subscriptionPlanModel: Model<SubscriptionPlanDocument>,
    @InjectModel(EventImage.name)
    private eventImageModel: Model<EventImageDocument>,
    private readonly eventMemberService: EventMemberService,
  ) {}

  private normalizeId(id: string | Types.ObjectId) {
    return String(id);
  }

  private toObjectId(id: string | Types.ObjectId) {
    return new Types.ObjectId(this.normalizeId(id));
  }

  private extractPermissionLimit(
    permissions: Record<string, unknown>[] = [],
    key: string,
  ) {
    for (const permission of permissions) {
      if (
        permission?.key === key &&
        permission.value !== undefined &&
        permission.value !== null
      ) {
        const numericValue = Number(permission.value);

        if (!Number.isNaN(numericValue)) {
          return numericValue;
        }
      }

      if (
        Object.prototype.hasOwnProperty.call(permission, key) &&
        permission[key] !== undefined &&
        permission[key] !== null
      ) {
        const numericValue = Number(permission[key]);

        if (!Number.isNaN(numericValue)) {
          return numericValue;
        }
      }
    }

    return 0;
  }

  private async getUserSubscriptionMeta(userId: string | Types.ObjectId) {
    const normalizedUserId = this.normalizeId(userId);

    if (!Types.ObjectId.isValid(normalizedUserId)) {
      return { maxPhotographers: null, planTitle: null as string | null };
    }

    const user = await this.userModel
      .findById(normalizedUserId)
      .select('isSubscriber subscriptionPlanId')
      .lean();

    if (!user?.isSubscriber || !user.subscriptionPlanId) {
      return { maxPhotographers: null, planTitle: null as string | null };
    }

    const plan = await this.subscriptionPlanModel
      .findById(user.subscriptionPlanId)
      .select('title permissions')
      .lean();

    return {
      maxPhotographers: null,
      planTitle: plan?.title ?? null,
    };
  }

  private async getOwnedEventOrThrow(
    eventId: string,
    actorId?: string,
    actorRole?: string,
  ) {
    return this.eventMemberService.assertCanManage(eventId, actorId, actorRole);
  }

  private toOwnerInvitationView(invitation: any) {
    const photographer = invitation.photographerId;

    return {
      _id: String(invitation._id),
      status: invitation.status,
      createdAt: invitation.createdAt,
      respondedAt: invitation.respondedAt ?? null,
      photographer: photographer
        ? {
            _id: String(photographer._id),
            name: photographer.name,
            email: photographer.email ?? null,
            phone: photographer.phone ?? null,
            userId: photographer.userId ?? null,
          }
        : null,
    };
  }

  private toPhotographerInvitationView(invitation: any) {
    const event = invitation.eventId;
    const inviter = invitation.userId;

    return {
      _id: String(invitation._id),
      status: invitation.status,
      createdAt: invitation.createdAt,
      respondedAt: invitation.respondedAt ?? null,
      event: event
        ? {
            _id: String(event._id),
            title: event.title,
            description: event.description ?? null,
            image: event.image ?? null,
          }
        : null,
      inviter: inviter
        ? {
            _id: String(inviter._id),
            name: inviter.name,
            email: inviter.email ?? null,
            phone: inviter.phone ?? null,
            userId: inviter.userId ?? null,
          }
        : null,
    };
  }

  async create(createEventDto: CreateEventDto, actorRole?: string) {
    const normalizedUserId = String(createEventDto.userId);

    if (!Types.ObjectId.isValid(normalizedUserId)) {
      throw new HttpException('Invalid user id', 400);
    }

    await this.eventMemberService.assertCanCreateOwnEvent(
      normalizedUserId,
      actorRole,
    );

    const event = await this.eventModel.create({
      ...createEventDto,
      userId: new Types.ObjectId(normalizedUserId),
    });

    if (!event) {
      throw new HttpException('Event not created', 400);
    }
    await this.eventMemberService.ensureOwnerMembership(
      String(event._id),
      normalizedUserId,
    );
    return { message: 'Event created successfully', data: event };
  }

  async findAllByUser(
    userId?: string,
    page = 1,
    limit = 10,
    workspace = 'all',
  ) {
    const safePage = Math.max(Number(page) || 1, 1);
    const safeLimit = Math.min(Math.max(Number(limit) || 10, 1), 100);
    const skip = (safePage - 1) * safeLimit;

    if (!userId) {
      return {
        data: [],
        page: safePage,
        limit: safeLimit,
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
        page: safePage,
        limit: safeLimit,
        totalItems: 0,
        totalPages: 0,
        hasNextPage: false,
        hasPreviousPage: false,
      };
    }

    const plannerOnly = workspace === 'planner';
    const [memberEventIds, legacyAcceptedInvites] = await Promise.all([
      this.eventMemberService.activeEventIds(
        normalizedUserId,
        plannerOnly
          ? [EventMemberRole.OWNER, EventMemberRole.EVENT_PLANNER]
          : undefined,
      ),
      plannerOnly
        ? Promise.resolve([])
        : this.eventInvitationModel
            .find({
              photographerId: this.toObjectId(normalizedUserId),
              status: EventInvitationStatus.ACCEPTED,
            })
            .select('eventId')
            .lean(),
    ]);
    const accessibleEventIds = [
      ...memberEventIds,
      ...legacyAcceptedInvites.map((item) =>
        this.toObjectId(String(item.eventId)),
      ),
    ];

    const filter: Record<string, unknown> = {
      $or: [
        { userId: new Types.ObjectId(normalizedUserId) },
        { userId: normalizedUserId as any },
        ...(accessibleEventIds.length
          ? [{ _id: { $in: accessibleEventIds } }]
          : []),
      ],
    };

    const [data, totalItems] = await Promise.all([
      this.eventModel
        .find(filter)
        .populate('userId', 'name email')
        .sort({ createdAt: -1 })
        .skip(skip)
        .limit(safeLimit)
        .lean()
        .exec(),
      this.eventModel.countDocuments(filter).exec(),
    ]);

    const subscription = await this.getUserSubscriptionMeta(normalizedUserId);
    const eventIds = data.map((event) => this.toObjectId(String(event._id)));

    const [invitations, photoCounts] = eventIds.length
      ? await Promise.all([
          this.eventInvitationModel
            .find({ eventId: { $in: eventIds } })
            .populate('photographerId', 'name email phone userId')
            .sort({ createdAt: -1 })
            .lean()
            .exec(),
          this.eventImageModel
            .aggregate<{
              _id: Types.ObjectId;
              count: number;
            }>([
              { $match: { eventId: { $in: eventIds } } },
              { $group: { _id: '$eventId', count: { $sum: 1 } } },
            ])
            .exec(),
        ])
      : [[], []];

    const teamSummaryMap =
      await this.eventMemberService.photographerSummaryByEventIds(eventIds);

    const photoCountMap = new Map(
      photoCounts.map((item) => [String(item._id), item.count]),
    );

    const invitationMap = new Map<
      string,
      ReturnType<typeof this.toOwnerInvitationView>[]
    >();

    invitations.forEach((invitation) => {
      const eventKey = this.normalizeId(invitation.eventId as Types.ObjectId);
      const current = invitationMap.get(eventKey) ?? [];
      current.push(this.toOwnerInvitationView(invitation));
      invitationMap.set(eventKey, current);
    });

    const enrichedData = data.map((event) => {
      const eventInvitations = invitationMap.get(String(event._id)) ?? [];
      const teamSummary = teamSummaryMap.get(String(event._id));
      const pendingInvites =
        teamSummary?.pendingInvites ??
        eventInvitations.filter(
          (invitation) => invitation.status === EventInvitationStatus.PENDING,
        ).length;
      const acceptedInvites =
        teamSummary?.acceptedInvites ??
        eventInvitations.filter(
          (invitation) => invitation.status === EventInvitationStatus.ACCEPTED,
        ).length;
      const totalInvited = teamSummary?.totalInvited ?? eventInvitations.length;

      return {
        ...event,
        invitations: eventInvitations,
        inviteSummary: {
          unlimitedPhotographers: true,
          maxPhotographers: null,
          totalInvited,
          pendingInvites,
          acceptedInvites,
          remainingInvites: null,
        },
        photosCount: photoCountMap.get(String(event._id)) ?? 0,
      };
    });

    const totalPages = Math.ceil(totalItems / safeLimit);

    return {
      data: enrichedData,
      page: safePage,
      limit: safeLimit,
      totalItems,
      totalPages,
      hasNextPage: safePage < totalPages,
      hasPreviousPage: safePage > 1,
      subscription: { ...subscription, unlimitedPhotographers: true },
    };
  }

  async findAll(query: EventFilterDto) {
    const { query: searchQuery, isPublished, isActive } = query;
    const page = Math.max(Number(query.page) || 1, 1);
    const limit = Math.min(Math.max(Number(query.limit) || 10, 1), 100);

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

  async findOne(id: string, userId?: string, role?: string) {
    await this.eventMemberService.assertCanAccess(id, userId, role);
    const event = await this.eventModel
      .findById(id)
      .populate('userId', 'name email phone')
      .lean();

    if (!event) {
      throw new HttpException('Event not found', 400);
    }

    return event;
  }

  async update(
    id: string,
    updateEventDto: UpdateEventDto,
    actorId?: string,
    actorRole?: string,
  ) {
    await this.eventMemberService.assertCanManage(id, actorId, actorRole);
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

  async remove(id: string, actorId?: string, actorRole?: string) {
    await this.eventMemberService.assertCanManage(id, actorId, actorRole);
    const event = await this.eventModel.findByIdAndDelete(id).lean();

    if (!event) {
      throw new HttpException('Event not found', 400);
    }

    await this.eventInvitationModel.deleteMany({
      eventId: this.toObjectId(String(event._id)),
    });

    return { message: 'Event deleted successfully', data: event };
  }

  async invitePhotographer(
    invitePhotographerDto: InvitePhotographerDto,
    actorId?: string,
    actorRole?: string,
  ) {
    const { eventId, photographerId } = invitePhotographerDto;
    const event = await this.getOwnedEventOrThrow(eventId, actorId, actorRole);

    if (!Types.ObjectId.isValid(photographerId)) {
      throw new HttpException('Invalid photographer id', 400);
    }

    const photographer = await this.userModel
      .findById(photographerId)
      .select('name email phone userId role isActive')
      .lean();

    if (!photographer?.isActive) {
      throw new HttpException('Active photographer not found', 400);
    }
    if (photographer.role !== UserType.PHOTOGRAPHER) {
      throw new HttpException('Selected user is not a photographer', 400);
    }

    const existingInvitation = await this.eventInvitationModel
      .findOne({
        eventId: this.toObjectId(eventId),
        photographerId: this.toObjectId(photographerId),
      })
      .lean();

    if (existingInvitation) {
      throw new HttpException(
        existingInvitation.status === EventInvitationStatus.ACCEPTED
          ? 'Photographer already joined this event'
          : 'Photographer already invited for this event',
        400,
      );
    }

    const createdInvitation = await this.eventInvitationModel.create({
      eventId: this.toObjectId(eventId),
      userId: this.toObjectId(event.userId),
      photographerId: this.toObjectId(photographerId),
      status: EventInvitationStatus.PENDING,
    });

    await this.eventMemberService.add(
      {
        eventId,
        userId: photographerId,
        role: 'photographer' as any,
        assignedAlbumIds: [],
        canPublish: true,
      },
      actorId || String(event.userId),
      actorRole,
    );

    const populatedInvitation = await this.eventInvitationModel
      .findById(createdInvitation._id)
      .populate('photographerId', 'name email phone userId')
      .lean();

    return {
      message: 'Photographer invited successfully',
      data: populatedInvitation
        ? this.toOwnerInvitationView(populatedInvitation)
        : null,
      meta: { unlimitedPhotographers: true, remainingInvites: null },
    };
  }

  async getMyPhotographerInvitations(photographerId?: string) {
    if (!photographerId || !Types.ObjectId.isValid(photographerId)) {
      return {
        data: [],
        totalItems: 0,
        pendingItems: 0,
        acceptedItems: 0,
      };
    }

    const data = await this.eventInvitationModel
      .find({ photographerId: this.toObjectId(photographerId) })
      .populate('eventId', 'title description image')
      .populate('userId', 'name email phone userId')
      .sort({ createdAt: -1 })
      .lean()
      .exec();

    return {
      data: data.map((invitation) =>
        this.toPhotographerInvitationView(invitation),
      ),
      totalItems: data.length,
      pendingItems: data.filter(
        (invitation) => invitation.status === EventInvitationStatus.PENDING,
      ).length,
      acceptedItems: data.filter(
        (invitation) => invitation.status === EventInvitationStatus.ACCEPTED,
      ).length,
    };
  }

  async acceptPhotographerInvitation(
    invitationId: string,
    photographerId?: string,
  ) {
    if (!photographerId || !Types.ObjectId.isValid(photographerId)) {
      throw new HttpException('Invalid photographer id', 400);
    }

    const invitation = await this.eventInvitationModel
      .findById(invitationId)
      .select('photographerId status eventId userId')
      .lean();

    if (!invitation) {
      throw new HttpException('Invitation not found', 400);
    }

    if (this.normalizeId(invitation.photographerId) !== photographerId) {
      throw new HttpException('You can only accept your own invitations', 403);
    }

    if (invitation.status !== EventInvitationStatus.PENDING) {
      throw new HttpException('Only pending invitations can be accepted', 400);
    }

    const updatedInvitation = await this.eventInvitationModel
      .findByIdAndUpdate(
        invitationId,
        {
          $set: {
            status: EventInvitationStatus.ACCEPTED,
            respondedAt: new Date(),
          },
        },
        { new: true },
      )
      .populate('eventId', 'title description image')
      .populate('userId', 'name email phone userId')
      .lean();

    await this.eventMemberService.activateLegacyPhotographer(
      String(invitation.eventId),
      photographerId,
      String(invitation.userId),
    );

    return {
      message: 'Invitation accepted successfully',
      data: updatedInvitation
        ? this.toPhotographerInvitationView(updatedInvitation)
        : null,
    };
  }

  async deletePhotographerInvitation(
    invitationId: string,
    photographerId?: string,
  ) {
    if (!photographerId || !Types.ObjectId.isValid(photographerId)) {
      throw new HttpException('Invalid photographer id', 400);
    }

    if (!Types.ObjectId.isValid(invitationId)) {
      throw new HttpException('Invalid invitation id', 400);
    }

    const invitation = await this.eventInvitationModel
      .findById(invitationId)
      .select('photographerId')
      .lean();

    if (!invitation) {
      throw new HttpException('Invitation not found', 400);
    }

    if (this.normalizeId(invitation.photographerId) !== photographerId) {
      throw new HttpException('You can only delete your own invitations', 403);
    }

    const deletedInvitation = await this.eventInvitationModel
      .findByIdAndDelete(invitationId)
      .lean();

    return {
      message: 'Invitation deleted successfully',
      data: deletedInvitation,
    };
  }

  async toggleActive(id: string, userId?: string, userRole?: string) {
    await this.eventMemberService.assertCanManage(id, userId, userRole);
    const event = await this.eventModel.findById(id).select('isActive').lean();
    if (!event) throw new HttpException('Event not found', 400);
    return this.eventModel
      .findByIdAndUpdate(
        id,
        { $set: { isActive: !event.isActive } },
        { new: true },
      )
      .lean();
  }

  async togglePublished(id: string, userId?: string, userRole?: string) {
    await this.eventMemberService.assertCanManage(id, userId, userRole);
    const event = await this.eventModel
      .findById(id)
      .select('isPublished')
      .lean();
    if (!event) throw new HttpException('Event not found', 400);
    return this.eventModel
      .findByIdAndUpdate(
        id,
        { $set: { isPublished: !event.isPublished } },
        { new: true },
      )
      .lean();
  }
}
