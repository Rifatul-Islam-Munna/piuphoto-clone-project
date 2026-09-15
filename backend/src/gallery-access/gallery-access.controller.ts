import {
  Body,
  Controller,
  Get,
  Patch,
  Post,
  Query,
  Req,
  UseGuards,
} from '@nestjs/common';
import { Throttle, ThrottlerGuard } from '@nestjs/throttler';
import { AuthGuard } from '../lib/auth.guard';
import type { ExpressRequest } from '../lib/auth.guard';
import {
  GalleryLinkDto,
  GallerySettingsDto,
  GalleryUnlockDto,
} from './dto/gallery-access.dto';
import { GalleryAccessService } from './gallery-access.service';

@Controller('gallery-access')
export class GalleryAccessController {
  constructor(private readonly service: GalleryAccessService) {}

  @Get('info')
  info(
    @Query('eventId') eventId: string,
    @Query('albumId') albumId?: string,
    @Query('accessToken') accessToken?: string,
  ) {
    return this.service.publicInfo(eventId, albumId, accessToken);
  }

  @Get('resolve')
  resolve(@Query('slug') slug?: string, @Query('domain') domain?: string) {
    return this.service.resolvePublicGallery(slug, domain);
  }

  @Get('settings')
  @UseGuards(AuthGuard)
  settings(@Query('eventId') eventId: string, @Req() req: ExpressRequest) {
    return this.service.getSettings(eventId, req.user.id, req.user.role);
  }

  @Patch('settings')
  @UseGuards(AuthGuard)
  update(@Body() dto: GallerySettingsDto, @Req() req: ExpressRequest) {
    return this.service.updateSettings(dto, req.user.id, req.user.role);
  }

  @Post('unlock')
  @UseGuards(ThrottlerGuard)
  @Throttle({ default: { limit: 12, ttl: 600000 } })
  unlock(@Body() dto: GalleryUnlockDto) {
    return this.service.unlock(dto);
  }

  @Post('private-link')
  @UseGuards(AuthGuard)
  privateLink(@Body() dto: GalleryLinkDto, @Req() req: ExpressRequest) {
    return this.service.createPrivateLink(dto, req.user.id, req.user.role);
  }

  @Post('revoke')
  @UseGuards(AuthGuard)
  revoke(@Body() dto: GalleryLinkDto, @Req() req: ExpressRequest) {
    return this.service.revoke(
      dto.eventId,
      dto.albumId,
      req.user.id,
      req.user.role,
    );
  }
}
