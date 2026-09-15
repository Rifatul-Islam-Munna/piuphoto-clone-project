import { Module } from '@nestjs/common';
import { MongooseModule } from '@nestjs/mongoose';
import { Event, EventSchema } from '../event/entities/event.entity';
import {
  EventInvitation,
  EventInvitationSchema,
} from '../event/entities/event-invitation.entity';
import { User, UserSchema } from '../user/entities/user.entity';
import { Album, AlbumSchema } from '../album/entities/album.entity';
import {
  SubscriptionPlan,
  SubscriptionPlanSchema,
} from '../subscription/entities/subscription-plan.entity';
import { EventMemberController } from './event-member.controller';
import { EventMemberService } from './event-member.service';
import { EventMember, EventMemberSchema } from './entities/event-member.entity';

@Module({
  imports: [
    MongooseModule.forFeature([
      { name: EventMember.name, schema: EventMemberSchema },
      { name: Event.name, schema: EventSchema },
      { name: EventInvitation.name, schema: EventInvitationSchema },
      { name: User.name, schema: UserSchema },
      { name: Album.name, schema: AlbumSchema },
      { name: SubscriptionPlan.name, schema: SubscriptionPlanSchema },
    ]),
  ],
  controllers: [EventMemberController],
  providers: [EventMemberService],
  exports: [EventMemberService, MongooseModule],
})
export class EventMemberModule {}
