import { Module } from '@nestjs/common';
import { MongooseModule } from '@nestjs/mongoose';
import { EventImageService } from './event-image.service';
import { EventImageController } from './event-image.controller';
import { EventImage, EventImageSchema } from './entities/event-image.entity';
import { Event, EventSchema } from '../event/entities/event.entity';
import { EventMemberModule } from '../event-member/event-member.module';
import { TransferStatusModule } from '../transfer-status/transfer-status.module';
import { Album, AlbumSchema } from '../album/entities/album.entity';
import {
  EventInvitation,
  EventInvitationSchema,
} from '../event/entities/event-invitation.entity';
import { User, UserSchema } from '../user/entities/user.entity';
import {
  SubscriptionPlan,
  SubscriptionPlanSchema,
} from '../subscription/entities/subscription-plan.entity';
import { FaceSearchModule } from '../face-search/face-search.module';
import { GalleryAccessModule } from '../gallery-access/gallery-access.module';
import { GuestGalleryModule } from '../guest-gallery/guest-gallery.module';
import {
  FalEnhancementJob,
  FalEnhancementJobSchema,
} from './entities/fal-enhancement-job.entity';
import { MediaAiService } from './media-ai.service';
import { RetouchWorkflowModule } from '../retouch-workflow/retouch-workflow.module';
import { WorkflowWebhookPublisherModule } from '../external-api/workflow-webhook-publisher.module';

@Module({
  imports: [
    EventMemberModule,
    TransferStatusModule,
    FaceSearchModule,
    GalleryAccessModule,
    GuestGalleryModule,
    RetouchWorkflowModule,
    WorkflowWebhookPublisherModule,
    MongooseModule.forFeature([
      { name: EventImage.name, schema: EventImageSchema },
      { name: Event.name, schema: EventSchema },
      { name: Album.name, schema: AlbumSchema },
      { name: EventInvitation.name, schema: EventInvitationSchema },
      { name: User.name, schema: UserSchema },
      { name: SubscriptionPlan.name, schema: SubscriptionPlanSchema },
      { name: FalEnhancementJob.name, schema: FalEnhancementJobSchema },
    ]),
  ],
  controllers: [EventImageController],
  providers: [EventImageService, MediaAiService],
  exports: [EventImageService, MediaAiService],
})
export class EventImageModule {}
