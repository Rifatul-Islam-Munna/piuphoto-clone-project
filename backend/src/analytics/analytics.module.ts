import { Module } from '@nestjs/common';
import { MongooseModule } from '@nestjs/mongoose';
import { EventMemberModule } from '../event-member/event-member.module';
import { Event, EventSchema } from '../event/entities/event.entity';
import { EventImage, EventImageSchema } from '../event-image/entities/event-image.entity';
import { FalEnhancementJob, FalEnhancementJobSchema } from '../event-image/entities/fal-enhancement-job.entity';
import { GuestFaceRegistration, GuestFaceRegistrationSchema } from '../guest-gallery/entities/guest-face-registration.entity';
import { GuestNotification, GuestNotificationSchema } from '../guest-gallery/entities/guest-notification.entity';
import { RetouchJob, RetouchJobSchema } from '../retouch-workflow/entities/retouch-job.entity';
import { StoreOrder, StoreOrderSchema } from '../store/entities/store-order.entity';
import { PhotoTransferStatus, PhotoTransferStatusSchema } from '../transfer-status/entities/photo-transfer-status.entity';
import { AnalyticsController } from './analytics.controller';
import { AnalyticsService } from './analytics.service';
import { AnalyticsEvent, AnalyticsEventSchema } from './entities/analytics-event.entity';
@Module({imports:[EventMemberModule,MongooseModule.forFeature([
  {name:AnalyticsEvent.name,schema:AnalyticsEventSchema},{name:Event.name,schema:EventSchema},{name:EventImage.name,schema:EventImageSchema},
  {name:FalEnhancementJob.name,schema:FalEnhancementJobSchema},{name:GuestFaceRegistration.name,schema:GuestFaceRegistrationSchema},{name:GuestNotification.name,schema:GuestNotificationSchema},
  {name:RetouchJob.name,schema:RetouchJobSchema},{name:StoreOrder.name,schema:StoreOrderSchema},{name:PhotoTransferStatus.name,schema:PhotoTransferStatusSchema},
])],controllers:[AnalyticsController],providers:[AnalyticsService],exports:[AnalyticsService]})
export class AnalyticsModule {}
