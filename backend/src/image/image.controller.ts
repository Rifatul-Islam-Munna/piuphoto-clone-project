import {
  Controller,
  Post,
  Delete,
  Body,
  UseGuards,
  UseInterceptors,
  UploadedFile,
  UploadedFiles,
  BadRequestException,
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
import { FileInterceptor, FilesInterceptor } from '@nestjs/platform-express';

const buildStorage = () =>
  diskStorage({
    destination: (req, file, cb) => {
      const uploadPath = join(cwd(), '/uploads');
      if (!existsSync(uploadPath)) {
        mkdirSync(uploadPath, { recursive: true });
      }
      cb(null, uploadPath);
    },
    filename: (req, file, cb) => {
      const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1e9);
      cb(null, `${uniqueSuffix}${extname(file.originalname)}`);
    },
  });

const imageUploadFilter = (req, file, callback) => {
  const allowedMimeTypes = new Set([
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/avif',
    'image/jpg',
    'image/heic',
    'image/heif',
    'image/tiff',
    'image/x-adobe-dng',
    'image/x-sony-arw',
    'image/x-canon-cr2',
    'image/x-canon-cr3',
    'image/x-nikon-nef',
    'image/x-fuji-raf',
    'image/x-panasonic-rw2',
    'image/x-olympus-orf',
    'application/pdf',
    'video/mp4',
    'video/webm',
    'video/ogg',
    'video/quicktime',
    'video/x-matroska',
  ]);
  const cameraExtensions = new Set([
    '.jpg', '.jpeg', '.png', '.webp', '.avif', '.heic', '.heif', '.tif', '.tiff',
    '.dng', '.arw', '.cr2', '.cr3', '.nef', '.nrw', '.raf', '.rw2', '.orf', '.pef',
  ]);
  const extension = extname(file.originalname || '').toLowerCase();
  const genericCameraFile =
    file.mimetype === 'application/octet-stream' && cameraExtensions.has(extension);

  if (!allowedMimeTypes.has(file.mimetype) && !genericCameraFile) {
    return callback(
      new BadRequestException('Unsupported image, camera RAW, PDF, or video file'),
      false,
    );
  }

  callback(null, true);
};

const cameraFileSizeLimit = 1024 * 1024 * 256;

const singleUploadOptions = {
  storage: buildStorage(),
  limits: { fileSize: cameraFileSizeLimit },
  fileFilter: imageUploadFilter,
};

const adminUploadOptions = {
  storage: buildStorage(),
  limits: { fileSize: cameraFileSizeLimit },
  fileFilter: imageUploadFilter,
};

const batchUploadOptions = {
  storage: buildStorage(),
  limits: { fileSize: cameraFileSizeLimit },
  fileFilter: imageUploadFilter,
};

@Controller('image')
export class ImageController {
  constructor(private readonly imageService: ImageService) {}

  @Post('upload')
  @UseGuards(AuthGuard)
  @ApiConsumes('multipart/form-data')
  @UseInterceptors(FileInterceptor('file', singleUploadOptions))
  uploadImage(@UploadedFile() file: any) {
    return this.imageService.uploadImage(file);
  }

  @Post('upload/batch')
  @UseGuards(AuthGuard)
  @ApiConsumes('multipart/form-data')
  @UseInterceptors(FilesInterceptor('files', 100, batchUploadOptions))
  uploadImages(@UploadedFiles() files: any[]) {
    return this.imageService.uploadImages(files);
  }

  @Post('upload-admin')
  @UseGuards(AuthGuard, RolesGuard)
  @Roles(UserType.ADMIN)
  @ApiConsumes('multipart/form-data')
  @UseInterceptors(FileInterceptor('file', adminUploadOptions))
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
