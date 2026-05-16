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

  async uploadImages(files: any[]) {
    if (!Array.isArray(files) || files.length === 0) {
      throw new HttpException('At least one file is required', HttpStatus.BAD_REQUEST);
    }

    try {
      const urls = await Promise.all(
        files.map(async (file) => this.minioService.uploadFile(file)),
      );

      return {
        message: 'Files uploaded successfully',
        urls,
      };
    } finally {
      await Promise.all(
        files.map(async (file) => {
          try {
            await unlink(file?.path);
          } catch (_) {}
        }),
      );
    }
  }

  async deleteImage(fileName: string) {
    const result = await this.minioService.deleteService(fileName);

    if (!result) {
      throw new HttpException('Failed to delete file', HttpStatus.INTERNAL_SERVER_ERROR);
    }

    return { message: 'File deleted successfully' };
  }
}
