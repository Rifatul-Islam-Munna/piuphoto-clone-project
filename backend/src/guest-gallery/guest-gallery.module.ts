import { Module } from '@nestjs/common';
import { MongooseModule } from '@nestjs/mongoose';
import { EventMemberModule } from '../event-member/event-member.module';
import {
  EventImage,
  EventImageSchema,
} from '../event-image/entities/event-image.entity';
import { Event, EventSchema } from '../event/entities/event.entity';
import { FaceSearchModule } from '../face-search/face-search.module';
import { GalleryAccessModule } from '../gallery-access/gallery-access.module';
import { NotificationModule } from '../notification/notification.module';
import {
  GuestFaceRegistration,
  GuestFaceRegistrationSchema,
} from './entities/guest-face-registration.entity';
import {
  GuestNotification,
  GuestNotificationSchema,
} from './entities/guest-notification.entity';
import { GuestGalleryController } from './guest-gallery.controller';
import { GuestGalleryService } from './guest-gallery.service';

@Module({
  imports: [
    EventMemberModule,
    FaceSearchModule,
    GalleryAccessModule,
    NotificationModule,
    MongooseModule.forFeature([
      { name: Event.name, schema: EventSchema },
      { name: EventImage.name, schema: EventImageSchema },
      { name: GuestFaceRegistration.name, schema: GuestFaceRegistrationSchema },
      { name: GuestNotification.name, schema: GuestNotificationSchema },
    ]),
  ],
  controllers: [GuestGalleryController],
  providers: [GuestGalleryService],
  exports: [GuestGalleryService],
})
export class GuestGalleryModule {}

