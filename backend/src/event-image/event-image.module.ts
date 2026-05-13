import { Module } from '@nestjs/common';
import { MongooseModule } from '@nestjs/mongoose';
import { EventImageService } from './event-image.service';
import { EventImageController } from './event-image.controller';
import { EventImage, EventImageSchema } from './entities/event-image.entity';
import { Event, EventSchema } from '../event/entities/event.entity';
import { Album, AlbumSchema } from '../album/entities/album.entity';
import {
  EventInvitation,
  EventInvitationSchema,
} from '../event/entities/event-invitation.entity';

@Module({
  imports: [
    MongooseModule.forFeature([
      { name: EventImage.name, schema: EventImageSchema },
      { name: Event.name, schema: EventSchema },
      { name: Album.name, schema: AlbumSchema },
      { name: EventInvitation.name, schema: EventInvitationSchema },
    ]),
  ],
  controllers: [EventImageController],
  providers: [EventImageService],
  exports: [EventImageService],
})
export class EventImageModule {}
