import { ForbiddenException } from '@nestjs/common';
import { Types } from 'mongoose';
import { EventMemberService } from './event-member.service';
import {
  EventMemberRole,
  EventMemberStatus,
} from './entities/event-member.entity';
import { UserType } from '../user/entities/user.entity';

describe('EventMemberService', () => {
  const userId = new Types.ObjectId().toHexString();
  const ownerId = new Types.ObjectId().toHexString();
  const eventId = new Types.ObjectId().toHexString();
  const albumId = new Types.ObjectId().toHexString();

  const queryResult = <T>(value: T) => ({
    select: jest.fn().mockReturnValue({
      lean: jest.fn().mockResolvedValue(value),
    }),
  });

  const createService = (memberModel: Record<string, jest.Mock>) =>
    new EventMemberService(
      memberModel as never,
      {
        findById: jest
          .fn()
          .mockReturnValue(
            queryResult({ _id: eventId, userId: ownerId, title: 'Event' }),
          ),
      } as never,
      {} as never,
      {
        findOne: jest.fn(),
      } as never,
      {} as never,
    );

  it('joins with a valid code and returns an active photographer membership', async () => {
    const event = {
      _id: new Types.ObjectId(eventId),
      userId: new Types.ObjectId(ownerId),
    };
    const findOne = jest.fn().mockReturnValue(queryResult(event));
    const findById = jest.fn().mockReturnValue(queryResult({ isActive: true }));
    const membership = {
      eventId: { _id: eventId, title: 'Event' },
      role: EventMemberRole.PHOTOGRAPHER,
      status: EventMemberStatus.ACTIVE,
    };
    const lean = jest.fn().mockResolvedValue(membership);
    const populateAlbums = jest.fn().mockReturnValue({ lean });
    const populateEvent = jest
      .fn()
      .mockReturnValue({ populate: populateAlbums });
    const findOneAndUpdate = jest
      .fn()
      .mockReturnValue({ populate: populateEvent });
    const service = new EventMemberService(
      { findOneAndUpdate } as never,
      { findOne } as never,
      { findById } as never,
      {} as never,
      {} as never,
    );

    await expect(service.joinByCode(' ab12cd34ef ', userId)).resolves.toEqual({
      message: 'Joined event as photographer',
      data: membership,
    });
    expect(findOne).toHaveBeenCalledWith({
      joinCode: 'AB12CD34EF',
      isActive: { $ne: false },
    });
    expect(findOneAndUpdate).toHaveBeenCalledWith(
      expect.objectContaining({
        eventId: event._id,
        role: EventMemberRole.PHOTOGRAPHER,
      }),
      expect.objectContaining({
        $set: expect.objectContaining({
          status: EventMemberStatus.ACTIVE,
          canPublish: true,
        }),
      }),
      expect.objectContaining({ upsert: true }),
    );
  });

  it('allows an older active user record without an explicit isActive property', async () => {
    const findOne = jest
      .fn()
      .mockReturnValue(
        queryResult({
          _id: new Types.ObjectId(eventId),
          userId: new Types.ObjectId(ownerId),
        }),
      );
    const findById = jest.fn().mockReturnValue(queryResult({}));
    const lean = jest.fn().mockResolvedValue({ eventId: { title: 'Event' } });
    const findOneAndUpdate = jest.fn().mockReturnValue({
      populate: jest.fn().mockReturnValue({
        populate: jest.fn().mockReturnValue({ lean }),
      }),
    });
    const service = new EventMemberService(
      { findOneAndUpdate } as never,
      { findOne } as never,
      { findById } as never,
      {} as never,
      {} as never,
    );
    await expect(
      service.joinByCode('AB12CD34EF', userId),
    ).resolves.toHaveProperty('message', 'Joined event as photographer');
  });

  it('exposes both workspaces when a planner account is also a photographer', async () => {
    const memberModel = {
      distinct: jest.fn().mockResolvedValue([EventMemberRole.PHOTOGRAPHER]),
    };
    const service = createService(memberModel);

    await expect(
      service.workspaceAccess(userId, UserType.USER),
    ).resolves.toEqual({
      planner: true,
      photographer: true,
      retoucher: true,
      reviewer: true,
      roles: [EventMemberRole.PHOTOGRAPHER],
    });
  });

  it('enforces assigned shooting categories for photographer memberships', async () => {
    const memberModel = {
      find: jest.fn().mockReturnValue(
        queryResult([
          {
            role: EventMemberRole.PHOTOGRAPHER,
            status: EventMemberStatus.ACTIVE,
            assignedAlbumIds: [new Types.ObjectId(albumId)],
          },
        ]),
      ),
    };
    const service = createService(memberModel);

    await expect(
      service.assertCanUpload(eventId, userId, UserType.PHOTOGRAPHER, albumId),
    ).resolves.toBeTruthy();

    await expect(
      service.assertCanUpload(
        eventId,
        userId,
        UserType.PHOTOGRAPHER,
        new Types.ObjectId().toHexString(),
      ),
    ).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('lets an active event planner upload even with a restricted photographer role', async () => {
    const memberModel = {
      find: jest.fn().mockReturnValue(
        queryResult([
          {
            role: EventMemberRole.PHOTOGRAPHER,
            assignedAlbumIds: [new Types.ObjectId(albumId)],
          },
          {
            role: EventMemberRole.EVENT_PLANNER,
            assignedAlbumIds: [],
          },
        ]),
      ),
    };
    const service = createService(memberModel);

    await expect(
      service.assertCanUpload(
        eventId,
        userId,
        UserType.PHOTOGRAPHER,
        undefined,
      ),
    ).resolves.toBeTruthy();
  });
});
