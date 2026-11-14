import { HttpException, HttpStatus, Injectable, Logger } from '@nestjs/common';
import { unlink } from 'fs/promises';
import { MinioService } from '../lib/minio.service';
import { PresignUploadDto } from './dto/presign-upload.dto';

@Injectable()
export class ImageService {
  private logger = new Logger(ImageService.name);

  constructor(private readonly minioService: MinioService) {}

  presignUpload(file: PresignUploadDto, requestOrigin?: string) {
    return this.minioService.presignUpload(file, requestOrigin);
  }

  async presignUploads(files: PresignUploadDto[], requestOrigin?: string) {
    return { uploads: await Promise.all(files.map((file) => this.presignUpload(file, requestOrigin))) };
  }

  async uploadImage(file: any, requestOrigin?: string) {
    if (!file) {
      throw new HttpException('File is required', HttpStatus.BAD_REQUEST);
    }

    const fileUrl = await this.uploadAndCleanTemporaryFile(file, requestOrigin);

    return { message: 'File uploaded successfully', url: fileUrl };
  }

  async uploadImages(files: any[], requestOrigin?: string) {
    if (!Array.isArray(files) || files.length === 0) {
      throw new HttpException('At least one file is required', HttpStatus.BAD_REQUEST);
    }

    // Each file owns its cleanup. A failed batch member must not delete another
    // member's temporary file while its cloud upload is still reading it.
    const urls = await Promise.all(
      files.map((file) => this.uploadAndCleanTemporaryFile(file, requestOrigin)),
    );

    return {
      message: 'Files uploaded successfully',
      urls,
    };
  }

  private async uploadAndCleanTemporaryFile(file: any, requestOrigin?: string): Promise<string> {
    try {
      return await this.minioService.uploadFile(file, requestOrigin);
    } finally {
      if (typeof file?.path === 'string' && file.path.length > 0) {
        try {
          await unlink(file.path);
        } catch (error) {
          const code = (error as NodeJS.ErrnoException)?.code;
          if (code !== 'ENOENT') {
            // Cleanup must not hide a successful cloud result, or replace the
            // original upload error. The phone retains its retry copy on failure.
            this.logger.warn(
              `Could not remove an upload temporary file (${code ?? 'unknown error'}).`,
            );
          }
        }
      }
    }
  }

  readImage(fileName: string, token: string) {
    return this.minioService.readFile(fileName, token);
  }

  async deleteImage(fileName: string) {
    const result = await this.minioService.deleteService(fileName);

    if (!result) {
      throw new HttpException('Failed to delete file', HttpStatus.INTERNAL_SERVER_ERROR);
    }

    return { message: 'File deleted successfully' };
  }
}
