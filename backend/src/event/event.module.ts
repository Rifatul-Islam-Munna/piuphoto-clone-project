import { Module } from '@nestjs/common';
import { EventService } from './event.service';
import { EventController } from './event.controller';
import { MongooseModule } from '@nestjs/mongoose';
import { Event, EventSchema } from './entities/event.entity';
import {
  EventInvitation,
  EventInvitationSchema,
} from './entities/event-invitation.entity';
import { User, UserSchema } from '../user/entities/user.entity';
import {
  SubscriptionPlan,
  SubscriptionPlanSchema,
} from '../subscription/entities/subscription-plan.entity';
import {
  EventImage,
  EventImageSchema,
} from '../event-image/entities/event-image.entity';

@Module({
  imports: [
    MongooseModule.forFeature([
      { name: Event.name, schema: EventSchema },
      { name: EventInvitation.name, schema: EventInvitationSchema },
      { name: User.name, schema: UserSchema },
      { name: SubscriptionPlan.name, schema: SubscriptionPlanSchema },
      { name: EventImage.name, schema: EventImageSchema },
    ]),
  ],
  controllers: [EventController],
  providers: [EventService],
  exports: [EventService],
})
export class EventModule {}
