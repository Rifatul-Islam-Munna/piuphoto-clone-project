import { Module } from '@nestjs/common';
import { EventImageModule } from '../event-image/event-image.module';
import { GuestGalleryModule } from '../guest-gallery/guest-gallery.module';
import { ImageModule } from '../image/image.module';
import { GalleryDownloadController } from './gallery-download.controller';
import { GalleryDownloadService } from './gallery-download.service';

@Module({
  imports: [EventImageModule, GuestGalleryModule, ImageModule],
  controllers: [GalleryDownloadController],
  providers: [GalleryDownloadService],
})
export class GalleryDownloadModule {}
