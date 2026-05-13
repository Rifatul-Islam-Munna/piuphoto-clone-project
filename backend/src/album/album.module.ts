import { Module } from '@nestjs/common';
import { MongooseModule } from '@nestjs/mongoose';
import { AlbumController } from './album.controller';
import { AlbumService } from './album.service';
import { Album, AlbumSchema } from './entities/album.entity';
import { Event, EventSchema } from '../event/entities/event.entity';
import {
  EventImage,
  EventImageSchema,
} from '../event-image/entities/event-image.entity';

@Module({
  imports: [
    MongooseModule.forFeature([
      { name: Album.name, schema: AlbumSchema },
      { name: Event.name, schema: EventSchema },
      { name: EventImage.name, schema: EventImageSchema },
    ]),
  ],
  controllers: [AlbumController],
  providers: [AlbumService],
  exports: [AlbumService],
})
export class AlbumModule {}
