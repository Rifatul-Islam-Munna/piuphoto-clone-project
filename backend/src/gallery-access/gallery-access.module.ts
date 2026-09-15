import { Module } from '@nestjs/common';
import { MongooseModule } from '@nestjs/mongoose';
import { Album, AlbumSchema } from '../album/entities/album.entity';
import { EventMemberModule } from '../event-member/event-member.module';
import { Event, EventSchema } from '../event/entities/event.entity';
import { GalleryAccessController } from './gallery-access.controller';
import { GalleryAccessService } from './gallery-access.service';
import {
  GalleryAccessAudit,
  GalleryAccessAuditSchema,
} from './gallery-access-audit.entity';

@Module({
  imports: [
    EventMemberModule,
    MongooseModule.forFeature([
      { name: Event.name, schema: EventSchema },
      { name: Album.name, schema: AlbumSchema },
      { name: GalleryAccessAudit.name, schema: GalleryAccessAuditSchema },
    ]),
  ],
  controllers: [GalleryAccessController],
  providers: [GalleryAccessService],
  exports: [GalleryAccessService],
})
export class GalleryAccessModule {}
