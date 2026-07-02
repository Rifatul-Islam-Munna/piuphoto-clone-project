import {
  Body,
  BadRequestException,
  Controller,
  Delete,
  Get,
  Patch,
  Post,
  Query,
  Req,
  UploadedFile,
  UseGuards,
  UseInterceptors,
} from '@nestjs/common';
import type { RawBodyRequest } from '@nestjs/common';
import { Throttle, ThrottlerGuard } from '@nestjs/throttler';
import { ApiConsumes } from '@nestjs/swagger';
import { FileInterceptor } from '@nestjs/platform-express';
import { memoryStorage } from 'multer';
import { EventImageService } from './event-image.service';
import {
  CreateEventImageDto,
  CreateEventImagesBatchDto,
  EnhanceEventImageDto,
  EventImageFilterDto,
  EventImageQueryDto,
  MyPictureDto,
} from './dto/create-event-image.dto';
import { UpdateEventImageDto } from './dto/update-event-image.dto';
import { AuthGuard } from '../lib/auth.guard';
import type { ExpressRequest } from '../lib/auth.guard';
import type { Request } from 'express';
import { FalWebhookDto, FalWebhookQueryDto } from './dto/fal-webhook.dto';

const faceSearchUploadOptions = {
  storage: memoryStorage(),
  limits: { fileSize: 1024 * 1024 * 50 },
  fileFilter: (req, file, callback) => {
    const allowedMimeTypes = ['image/jpeg', 'image/png', 'image/webp', 'image/jpg'];

    if (!allowedMimeTypes.includes(file.mimetype)) {
      return callback(
        new BadRequestException('Only image files are allowed'),
        false,
      );
    }

    callback(null, true);
  },
};

@Controller('eventImage')
export class EventImageController {
  constructor(private readonly eventImageService: EventImageService) {}

  @Post()
  @UseGuards(AuthGuard, ThrottlerGuard)
  @Throttle({ default: { limit: 500, ttl: 3600000 } })
  create(
    @Body() createEventImageDto: CreateEventImageDto,
    @Req() req: ExpressRequest,
  ) {
    return this.eventImageService.create(
      createEventImageDto,
      req.user?.id,
      req.user?.role,
    );
  }

  @Post('fal-webhook')
  async falWebhook(
    @Query() query: FalWebhookQueryDto,
    @Body() body: FalWebhookDto,
    @Req() req: RawBodyRequest<Request>,
  ) {
    await this.eventImageService.verifyFalWebhookSignature(
      req.headers,
      req.rawBody,
    );
    return this.eventImageService.handleFalWebhook(query.type, body);
  }

  @Post('batch')
  @UseGuards(AuthGuard, ThrottlerGuard)
  @Throttle({ default: { limit: 500, ttl: 3600000 } })
  createBatch(
    @Body() createEventImagesBatchDto: CreateEventImagesBatchDto,
    @Req() req: ExpressRequest,
  ) {
    return this.eventImageService.createMany(
      createEventImagesBatchDto,
      req.user?.id,
      req.user?.role,
    );
  }

  @Get('get-all')
  @UseGuards(AuthGuard)
  findAll(@Query() query: EventImageFilterDto) {
    return this.eventImageService.findAll(query);
  }

  @Get('public')
  findPublic(
    @Query('eventId') eventId: string,
    @Query('albumId') albumId?: string,
  ) {
    return this.eventImageService.findPublicByEvent(eventId, albumId);
  }

  @Get('get-one')
  @UseGuards(AuthGuard)
  findOne(@Query() query: EventImageQueryDto) {
    return this.eventImageService.findOne(query.id);
  }

  @Patch('update')
  @UseGuards(AuthGuard)
  update(
    @Query() query: EventImageQueryDto,
    @Body() updateEventImageDto: UpdateEventImageDto,
    @Req() req: ExpressRequest,
  ) {
    return this.eventImageService.update(
      query.id,
      updateEventImageDto,
      req.user?.id,
      req.user?.role,
    );
  }

  @Post('enhance')
  @UseGuards(AuthGuard, ThrottlerGuard)
  @Throttle({ default: { limit: 200, ttl: 3600000 } })
  enhance(
    @Body() body: EnhanceEventImageDto,
    @Req() req: ExpressRequest,
  ) {
    return this.eventImageService.enhanceExisting(
      body.id,
      req.user?.id,
      req.user?.role,
      body.prompt,
    );
  }

  @Post('my-picture')
  @UseGuards(AuthGuard, ThrottlerGuard)
  @Throttle({ default: { limit: 100, ttl: 3600000 } })
  @ApiConsumes('multipart/form-data')
  @UseInterceptors(FileInterceptor('image', faceSearchUploadOptions))
  myPicture(
    @UploadedFile() file: Express.Multer.File,
    @Query() query: MyPictureDto,
    @Req() req: ExpressRequest,
  ) {
    return this.eventImageService.findMyPictures(
      file,
      query,
      req.user?.id,
      req.user?.role,
    );
  }

  @Post('public/my-picture')
  @UseGuards(ThrottlerGuard)
  @Throttle({ default: { limit: 100, ttl: 3600000 } })
  @ApiConsumes('multipart/form-data')
  @UseInterceptors(FileInterceptor('image', faceSearchUploadOptions))
  publicMyPicture(
    @UploadedFile() file: Express.Multer.File,
    @Query() query: MyPictureDto,
  ) {
    return this.eventImageService.findMyPictures(
      file,
      query,
      undefined,
      undefined,
      true,
    );
  }

  @Delete('delete')
  @UseGuards(AuthGuard)
  remove(@Query() query: EventImageQueryDto, @Req() req: ExpressRequest) {
    return this.eventImageService.remove(query.id, req.user?.id, req.user?.role);
  }
}
