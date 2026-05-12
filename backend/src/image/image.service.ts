import { HttpException, HttpStatus, Injectable, Logger } from '@nestjs/common';
import { unlink } from 'fs/promises';
import { MinioService } from '../lib/minio.service';

@Injectable()
export class ImageService {
  private logger = new Logger(ImageService.name);

  constructor(private readonly minioService: MinioService) {}

  async uploadImage(file: any) {
    if (!file) {
      throw new HttpException('File is required', HttpStatus.BAD_REQUEST);
    }

    const fileUrl = await this.minioService.uploadFile(file);
    await unlink(file?.path);

    return { message: 'File uploaded successfully', url: fileUrl };
  }

  async deleteImage(fileName: string) {
    const result = await this.minioService.deleteService(fileName);

    if (!result) {
      throw new HttpException('Failed to delete file', HttpStatus.INTERNAL_SERVER_ERROR);
    }

    return { message: 'File deleted successfully' };
  }
}