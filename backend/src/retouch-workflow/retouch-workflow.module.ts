import { Module } from '@nestjs/common';
import { MongooseModule } from '@nestjs/mongoose';
import { EventMemberModule } from '../event-member/event-member.module';
import { TransferStatusModule } from '../transfer-status/transfer-status.module';
import { EventMember, EventMemberSchema } from '../event-member/entities/event-member.entity';
import { Event, EventSchema } from '../event/entities/event.entity';
import { EventImage, EventImageSchema } from '../event-image/entities/event-image.entity';
import { PhotoVersion, PhotoVersionSchema } from './entities/photo-version.entity';
import { RetouchJob, RetouchJobSchema } from './entities/retouch-job.entity';
import { RetouchWorkflowSettings, RetouchWorkflowSettingsSchema } from './entities/retouch-workflow-settings.entity';
import { RetouchWorkflowController } from './retouch-workflow.controller';
import { WorkflowWebhookPublisherModule } from '../external-api/workflow-webhook-publisher.module';
import { RetouchWorkflowService } from './retouch-workflow.service';

@Module({
  imports: [
    EventMemberModule,
    TransferStatusModule,
    WorkflowWebhookPublisherModule,
    MongooseModule.forFeature([
      { name: RetouchJob.name, schema: RetouchJobSchema },
      { name: PhotoVersion.name, schema: PhotoVersionSchema },
      { name: RetouchWorkflowSettings.name, schema: RetouchWorkflowSettingsSchema },
      { name: EventImage.name, schema: EventImageSchema },
      { name: Event.name, schema: EventSchema },
      { name: EventMember.name, schema: EventMemberSchema },
    ]),
  ],
  controllers: [RetouchWorkflowController],
  providers: [RetouchWorkflowService],
  exports: [RetouchWorkflowService],
})
export class RetouchWorkflowModule {}
