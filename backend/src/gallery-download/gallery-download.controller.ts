import { Controller, Get, Query, Res, UseGuards } from '@nestjs/common';
import { Throttle, ThrottlerGuard } from '@nestjs/throttler';
import type { Response } from 'express';
import { GalleryDownloadService } from './gallery-download.service';

/** Native browser attachment, never an app:// deep link. */
@Controller('public-downloads')
export class GalleryDownloadController {
  constructor(private readonly downloads: GalleryDownloadService) {}

  @Get('event-photo')
  @UseGuards(ThrottlerGuard)
  @Throttle({ default: { limit: 30, ttl: 3600000 } })
  photo(
    @Query('eventId') eventId: string,
    @Query('albumId') albumId: string | undefined,
    @Query('accessToken') accessToken: string | undefined,
    @Query('guestToken') guestToken: string | undefined,
    @Query('ids') ids: string,
    @Res() res: Response,
  ) {
    return this.downloads.downloadPhoto(
      { eventId, albumId, accessToken, guestToken, ids }, res,
    );
  }

  @Get('event-photos.zip')
  @UseGuards(ThrottlerGuard)
  @Throttle({ default: { limit: 12, ttl: 3600000 } })
  download(
    @Query('eventId') eventId: string,
    @Query('albumId') albumId: string | undefined,
    @Query('accessToken') accessToken: string | undefined,
    @Query('guestToken') guestToken: string | undefined,
    @Query('ids') ids: string | undefined,
    @Res() res: Response,
  ) {
    return this.downloads.download(
      { eventId, albumId, accessToken, guestToken, ids }, res,
    );
  }
}
