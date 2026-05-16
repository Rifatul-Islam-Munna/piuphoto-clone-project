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
};

const singleUploadOptions = {
  storage: buildStorage(),
  limits: { fileSize: 1024 * 1024 * 20 },
  fileFilter: imageUploadFilter,
};

const adminUploadOptions = {
  storage: buildStorage(),
  limits: { fileSize: 1024 * 1024 * 50 },
  fileFilter: imageUploadFilter,
};

const batchUploadOptions = {
  storage: buildStorage(),
  limits: { fileSize: 1024 * 1024 * 20 },
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
