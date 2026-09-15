import { Body, Controller, Get, Patch, Post, Query, Req, Sse, UseGuards } from '@nestjs/common';
import { AuthGuard } from '../lib/auth.guard';
import type { ExpressRequest } from '../lib/auth.guard';
import { AssignRetouchDto, BulkReviewRetouchDto, DesktopFeedDto, DesktopHeartbeatDto, RetouchListDto, RetouchSettingsDto, RetouchStatusDto, RetouchVersionDto, ReviewRetouchDto, UnassignRetouchDto } from './dto/retouch.dto';
import { RetouchWorkflowService } from './retouch-workflow.service';

@Controller('retouch')
@UseGuards(AuthGuard)
export class RetouchWorkflowController {
  constructor(private readonly service: RetouchWorkflowService) {}

  @Get('jobs') list(@Query() query: RetouchListDto, @Req() req: ExpressRequest) {
    return this.service.list(query, req.user?.id, req.user?.role);
  }
  @Post('assign') assign(@Body() body: AssignRetouchDto, @Req() req: ExpressRequest) {
    return this.service.assign(body, req.user?.id, req.user?.role);
  }
  @Post('unassign') unassign(@Body() body: UnassignRetouchDto, @Req() req: ExpressRequest) {
    return this.service.unassign(body.eventId, body.jobIds, req.user?.id, req.user?.role);
  }
  @Patch('status') status(@Body() body: RetouchStatusDto, @Req() req: ExpressRequest) {
    return this.service.updateStatus(body, req.user?.id, req.user?.role);
  }
  @Post('version') version(@Body() body: RetouchVersionDto, @Req() req: ExpressRequest) {
    return this.service.uploadVersion(body, req.user?.id, req.user?.role);
  }
  @Patch('review') review(@Body() body: ReviewRetouchDto, @Req() req: ExpressRequest) {
    return this.service.review(body, req.user?.id, req.user?.role);
  }
  @Patch('review-batch') reviewBatch(@Body() body: BulkReviewRetouchDto, @Req() req: ExpressRequest) {
    return this.service.bulkReview(body, req.user?.id, req.user?.role);
  }
  @Get('versions') versions(@Query('jobId') jobId: string, @Req() req: ExpressRequest) {
    return this.service.versions(jobId, req.user?.id, req.user?.role);
  }
  @Get('settings') settings(@Query('eventId') eventId: string, @Req() req: ExpressRequest) {
    return this.service.getSettings(eventId, req.user?.id, req.user?.role);
  }
  @Patch('settings') updateSettings(@Body() body: RetouchSettingsDto, @Req() req: ExpressRequest) {
    return this.service.updateSettings(body, req.user?.id, req.user?.role);
  }
  @Get('desktop-feed') desktopFeed(@Query() query: DesktopFeedDto, @Req() req: ExpressRequest) {
    return this.service.desktopFeed(query, req.user?.id, req.user?.role);
  }
  @Get('desktop-status') desktopStatus(@Query('eventId') eventId: string, @Req() req: ExpressRequest) {
    return this.service.desktopStatus(eventId, req.user?.id, req.user?.role);
  }
  @Post('desktop-heartbeat') heartbeat(@Body() body: DesktopHeartbeatDto, @Req() req: ExpressRequest) {
    return this.service.heartbeat(body.eventId, body.deviceId, req.user?.id, req.user?.role);
  }
  @Sse('stream') stream(@Query('eventId') eventId: string, @Req() req: ExpressRequest) {
    return this.service.stream(eventId, req.user?.id, req.user?.role);
  }
}
