import {
  Controller,
  Post,
  Delete,
  Body,
  UseGuards,
  UseInterceptors,
  UploadedFile,
  BadRequestException,
  Logger,
  Query,
} from '@nestjs/common';
import { ImageService } from './image.service';
import { AuthGuard } from '../lib/auth.guard';
import { RolesGuard } from '../lib/roles.guard';
import { Roles } from '../lib/roles.decorator';
import { UserType } from '../user/entities/user.entity';
import { ApiConsumes } from '@nestjs/swagger';
import { existsSync, mkdirSync } from 'fs';
import { diskStorage } from 'multer';
import { extname, join } from 'path';
import { cwd } from 'process';
import { FileInterceptor } from '@nestjs/platform-express';

@Controller('image')
export class ImageController {
  private logger = new Logger(ImageController.name);

  constructor(private readonly imageService: ImageService) {}

  @Post('upload')
  @UseGuards(AuthGuard)
  @ApiConsumes('multipart/form-data')
  @UseInterceptors(
    FileInterceptor('file', {
      storage: diskStorage({
        destination: (req, file, cb) => {
          const uploadPath = join(cwd(), '/uploads');
          if (!existsSync(uploadPath)) {
            mkdirSync(uploadPath, { recursive: true });
          }
          cb(null, uploadPath);
        },
        filename: (req, file, cb) => {
          const uniqueSuffix =
            Date.now() + '-' + Math.round(Math.random() * 1e9);
          cb(null, `${uniqueSuffix}${extname(file.originalname)}`);
        },
      }),
      limits: { fileSize: 1024 * 1024 * 20 },
      fileFilter: (req, file, callback) => {
        const allowedMimeTypes = [
          'image/jpeg',
          'image/png',
          'image/webp',
          'image/avif',
          'image/jpg',
          'application/pdf',
          'video/mp4',
          'video/webm',
          'video/ogg',
          'video/quicktime',
          'video/x-matroska',
        ];

        if (!allowedMimeTypes.includes(file.mimetype)) {
          return callback(
            new BadRequestException('Only PDF and image files are allowed'),
            false,
          );
        }

        callback(null, true);
      },
    }),
  )
  uploadImage(@UploadedFile() file: any) {
    return this.imageService.uploadImage(file);
  }

  @Post('upload-admin')
  @UseGuards(AuthGuard, RolesGuard)
  @Roles(UserType.ADMIN)
  @ApiConsumes('multipart/form-data')
  @UseInterceptors(
    FileInterceptor('file', {
      storage: diskStorage({
        destination: (req, file, cb) => {
          const uploadPath = join(cwd(), '/uploads');
          if (!existsSync(uploadPath)) {
            mkdirSync(uploadPath, { recursive: true });
          }
          cb(null, uploadPath);
        },
        filename: (req, file, cb) => {
          const uniqueSuffix =
            Date.now() + '-' + Math.round(Math.random() * 1e9);
          cb(null, `${uniqueSuffix}${extname(file.originalname)}`);
        },
      }),
      limits: { fileSize: 1024 * 1024 * 50 },
      fileFilter: (req, file, callback) => {
        const allowedMimeTypes = [
          'image/jpeg',
          'image/png',
          'image/webp',
          'image/avif',
          'image/jpg',
          'application/pdf',
          'video/mp4',
          'video/webm',
          'video/ogg',
          'video/quicktime',
          'video/x-matroska',
        ];

        if (!allowedMimeTypes.includes(file.mimetype)) {
          return callback(
            new BadRequestException('Only PDF and image files are allowed'),
            false,
          );
        }

        callback(null, true);
      },
    }),
  )
  uploadImageAdmin(@UploadedFile() file: any) {
    return this.imageService.uploadImage(file);
  }

  @Delete('delete')
  @UseGuards(AuthGuard, RolesGuard)
  @Roles(UserType.ADMIN)
  deleteImage(@Body('fileName') fileName: string) {
    return this.imageService.deleteImage(fileName);
  }
}