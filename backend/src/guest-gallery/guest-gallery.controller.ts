import {
  BadRequestException,
  Body,
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
import { FileInterceptor } from '@nestjs/platform-express';
import { Throttle, ThrottlerGuard } from '@nestjs/throttler';
import { memoryStorage } from 'multer';
import { AuthGuard } from '../lib/auth.guard';
import type { ExpressRequest } from '../lib/auth.guard';
import {
  DeleteGuestDto,
  PersonalGalleryQueryDto,
  RegisterGuestDto,
  UpdateGuestPreferencesDto,
} from './dto/guest-gallery.dto';
import { GuestGalleryService } from './guest-gallery.service';

const selfieOptions = {
  storage: memoryStorage(),
  limits: { fileSize: 20 * 1024 * 1024 },
  fileFilter: (_req, file, callback) => {
    if (
      !['image/jpeg', 'image/png', 'image/webp', 'image/jpg'].includes(
        file.mimetype,
      )
    ) {
      return callback(
        new BadRequestException('Only JPG, PNG or WEBP selfies are allowed'),
        false,
      );
    }
    callback(null, true);
  },
};

@Controller('guest-gallery')
export class GuestGalleryController {
  constructor(private readonly service: GuestGalleryService) {}

  @Post('register')
  @UseGuards(ThrottlerGuard)
  @Throttle({ default: { limit: 30, ttl: 3600000 } })
  @UseInterceptors(FileInterceptor('selfie', selfieOptions))
  register(
    @UploadedFile() file: Express.Multer.File,
    @Body() dto: RegisterGuestDto,
  ) {
    return this.service.register(file, dto);
  }

  @Get('personal')
  personal(@Query() query: PersonalGalleryQueryDto) {
    return this.service.personal(query);
  }

  @Post('delete')
  remove(@Body() dto: DeleteGuestDto) {
    return this.service.deleteRegistration(dto);
  }

  @Patch('preferences')
  preferences(@Body() dto: UpdateGuestPreferencesDto) {
    return this.service.updatePreferences(dto);
  }

  @Get('notifications')
  @UseGuards(AuthGuard)
  status(@Query('eventId') eventId: string, @Req() req: ExpressRequest) {
    return this.service.plannerStatus(eventId, req.user.id, req.user.role);
  }
}
