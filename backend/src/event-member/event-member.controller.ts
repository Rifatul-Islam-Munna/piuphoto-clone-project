import {
  Body,
  Controller,
  Delete,
  Get,
  Patch,
  Post,
  Query,
  Req,
  UseGuards,
} from '@nestjs/common';
import { AuthGuard } from '../lib/auth.guard';
import type { ExpressRequest } from '../lib/auth.guard';
import {
  AddEventMemberDto,
  UpdateEventMemberDto,
  JoinEventByCodeDto,
} from './dto/event-member.dto';
import { EventMemberService } from './event-member.service';

@Controller('event-members')
@UseGuards(AuthGuard)
export class EventMemberController {
  constructor(private readonly service: EventMemberService) {}

  @Post()
  add(@Body() dto: AddEventMemberDto, @Req() req: ExpressRequest) {
    return this.service.add(dto, req.user.id, req.user.role);
  }

  @Get()
  list(@Query('eventId') eventId: string, @Req() req: ExpressRequest) {
    return this.service.list(eventId, req.user.id, req.user.role);
  }

  @Get('mine')
  mine(@Req() req: ExpressRequest) {
    return this.service.myMemberships(req.user.id);
  }

  @Get('workspaces')
  workspaces(@Req() req: ExpressRequest) {
    return this.service.workspaceAccess(req.user.id, req.user.role);
  }
  @Post('join-code')
  joinCode(@Query('eventId') eventId: string, @Req() req: ExpressRequest) {
    return this.service.getOrCreateJoinCode(
      eventId,
      req.user.id,
      req.user.role,
    );
  }

  @Patch('join-code/rotate')
  rotateJoinCode(
    @Query('eventId') eventId: string,
    @Req() req: ExpressRequest,
  ) {
    return this.service.getOrCreateJoinCode(
      eventId,
      req.user.id,
      req.user.role,
      true,
    );
  }

  @Post('join')
  join(@Body() dto: JoinEventByCodeDto, @Req() req: ExpressRequest) {
    return this.service.joinByCode(dto.code, req.user.id);
  }

  @Patch('accept')
  accept(@Query('id') id: string, @Req() req: ExpressRequest) {
    return this.service.accept(id, req.user.id);
  }

  @Patch()
  update(
    @Query('id') id: string,
    @Body() dto: UpdateEventMemberDto,
    @Req() req: ExpressRequest,
  ) {
    return this.service.update(id, dto, req.user.id, req.user.role);
  }

  @Delete('mine')
  leave(@Query('id') id: string, @Req() req: ExpressRequest) {
    return this.service.leave(id, req.user.id);
  }
  @Delete()
  remove(@Query('id') id: string, @Req() req: ExpressRequest) {
    return this.service.remove(id, req.user.id, req.user.role);
  }
}
