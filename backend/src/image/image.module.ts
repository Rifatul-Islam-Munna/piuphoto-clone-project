import { Module } from '@nestjs/common';
import { ImageService } from './image.service';
import { ImageController } from './image.controller';
import { MinioService } from '../lib/minio.service';

@Module({
  controllers: [ImageController],
  providers: [ImageService, MinioService],
  exports: [ImageService],
})
export class ImageModule {}