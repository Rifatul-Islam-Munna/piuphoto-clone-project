import { Body, Controller, Get, Post, Query, Req, Sse, UseGuards } from '@nestjs/common';
import { Throttle, ThrottlerGuard } from '@nestjs/throttler';
import { AuthGuard } from '../lib/auth.guard';
import type { ExpressRequest } from '../lib/auth.guard';
import { TransferStatusQueryDto, UpsertTransferStatusDto } from './dto/transfer-status.dto';
import { TransferStatusService } from './transfer-status.service';

@Controller('transfer-status')
@UseGuards(AuthGuard)
export class TransferStatusController {
  constructor(private readonly service: TransferStatusService) {}

  @Post()
  @UseGuards(ThrottlerGuard)
  @Throttle({ default: { limit: 3000, ttl: 3600000 } })
  upsert(@Body() dto: UpsertTransferStatusDto, @Req() req: ExpressRequest) {
    return this.service.upsert(dto, req.user.id, req.user.role);
  }

  @Get()
  list(@Query() query: TransferStatusQueryDto, @Req() req: ExpressRequest) {
    return this.service.list(query, req.user.id, req.user.role);
  }

  @Sse('stream')
  stream(@Query('eventId') eventId: string, @Req() req: ExpressRequest) {
    return this.service.stream(eventId, req.user.id, req.user.role);
  }
}
