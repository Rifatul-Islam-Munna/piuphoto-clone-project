import { Controller, Get, Query, Req, UseGuards } from '@nestjs/common';
import { AuthGuard } from '../lib/auth.guard';
import type { ExpressRequest } from '../lib/auth.guard';
import { UploadSessionService } from './upload-session.service';

@Controller('upload-sessions')
@UseGuards(AuthGuard)
export class UploadSessionController {
  constructor(private readonly service: UploadSessionService) {}

  @Get()
  list(@Query('eventId') eventId: string, @Req() req: ExpressRequest) {
    return this.service.listForEvent(eventId, req.user.id, req.user.role);
  }
}
