import { Body, Controller, Get, Post, Query, Req, UseGuards } from '@nestjs/common';
import { Throttle, ThrottlerGuard } from '@nestjs/throttler';
import type { Request } from 'express';
import { AuthGuard } from '../lib/auth.guard';
import type { ExpressRequest } from '../lib/auth.guard';
import { AnalyticsService } from './analytics.service';
import { AnalyticsSummaryDto, TrackAnalyticsDto } from './dto/analytics.dto';
@Controller('analytics')
export class AnalyticsController {
  constructor(private readonly service:AnalyticsService){}
  @Post('track') @UseGuards(ThrottlerGuard) @Throttle({default:{limit:300,ttl:3600000}}) track(@Body() body:TrackAnalyticsDto,@Req() req:Request){ const raw=`${req.ip||''}|${req.headers['user-agent']||''}|${body.eventId}`; return this.service.track(body,this.service.fingerprint(raw)); }
  @Get('summary') @UseGuards(AuthGuard) summary(@Query() query:AnalyticsSummaryDto,@Req() req:ExpressRequest){ return this.service.summary(query,req.user?.id,req.user?.role); }
}
