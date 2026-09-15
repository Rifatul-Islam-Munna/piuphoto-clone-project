import {
  Controller,
  Get,
  Post,
  Patch,
  Delete,
  Body,
  Query,
  UseGuards,
  Req,
} from '@nestjs/common';
import { EventService } from './event.service';
import {
  CreateEventDto,
  UpdateEventDto,
  EventFilterDto,
} from './dto/create-event.dto';
import {
  EventInvitationQueryDto,
  InvitePhotographerDto,
} from './dto/event-invitation.dto';
import { AuthGuard } from '../lib/auth.guard';
import { RolesGuard } from '../lib/roles.guard';
import { Roles } from '../lib/roles.decorator';
import { UserType } from '../user/entities/user.entity';
import { Throttle, ThrottlerGuard } from '@nestjs/throttler';
import type { ExpressRequest } from '../lib/auth.guard';

@Controller('event')
export class EventController {
  constructor(private readonly eventService: EventService) {}

  @Post()
  @UseGuards(AuthGuard, RolesGuard, ThrottlerGuard)
  @Roles(UserType.USER, UserType.EDITOR, UserType.ADMIN)
  @Throttle({ default: { limit: 100, ttl: 3600000 } })
  create(@Body() createEventDto: CreateEventDto, @Req() req: ExpressRequest) {
    const targetUserId =
      req.user?.role === UserType.ADMIN && createEventDto.userId
        ? String(createEventDto.userId)
        : String(req.user?.id);

    return this.eventService.create({
      ...createEventDto,
      userId: targetUserId,
    });
  }

  @Get('my-events')
  @UseGuards(AuthGuard)
  getMyEvents(@Req() req: ExpressRequest, @Query() query: EventFilterDto) {
    return this.eventService.findAllByUser(
      req.user?.id,
      Number(query.page) || 1,
      Number(query.limit) || 10,
      query.workspace,
    );
  }

  @Post('invite-photographer')
  @UseGuards(AuthGuard, ThrottlerGuard)
  @Throttle({ default: { limit: 200, ttl: 3600000 } })
  invitePhotographer(
    @Body() invitePhotographerDto: InvitePhotographerDto,
    @Req() req: ExpressRequest,
  ) {
    return this.eventService.invitePhotographer(
      invitePhotographerDto,
      req.user?.id,
      req.user?.role,
    );
  }

  @Get('my-photographer-invitations')
  @UseGuards(AuthGuard, RolesGuard)
  @Roles(UserType.PHOTOGRAPHER)
  getMyPhotographerInvitations(@Req() req: ExpressRequest) {
    return this.eventService.getMyPhotographerInvitations(req.user?.id);
  }

  @Patch('accept-invitation')
  @UseGuards(AuthGuard, RolesGuard, ThrottlerGuard)
  @Throttle({ default: { limit: 200, ttl: 3600000 } })
  @Roles(UserType.PHOTOGRAPHER)
  acceptInvitation(
    @Query() query: EventInvitationQueryDto,
    @Req() req: ExpressRequest,
  ) {
    return this.eventService.acceptPhotographerInvitation(
      query.id,
      req.user?.id,
    );
  }

  @Delete('delete-invitation')
  @UseGuards(AuthGuard, RolesGuard, ThrottlerGuard)
  @Throttle({ default: { limit: 200, ttl: 3600000 } })
  @Roles(UserType.PHOTOGRAPHER)
  deleteInvitation(
    @Query() query: EventInvitationQueryDto,
    @Req() req: ExpressRequest,
  ) {
    return this.eventService.deletePhotographerInvitation(
      query.id,
      req.user?.id,
    );
  }

  @Get('get-all')
  @UseGuards(AuthGuard, RolesGuard)
  @Roles(UserType.ADMIN)
  findAll(@Query() query: EventFilterDto) {
    return this.eventService.findAll(query);
  }

  @Get('get-one')
  @UseGuards(AuthGuard)
  findOne(@Query('id') id: string, @Req() req: ExpressRequest) {
    return this.eventService.findOne(id, req.user?.id, req.user?.role);
  }

  @Patch('update')
  @UseGuards(AuthGuard)
  update(
    @Query('id') id: string,
    @Body() updateEventDto: UpdateEventDto,
    @Req() req: ExpressRequest,
  ) {
    return this.eventService.update(
      id,
      updateEventDto,
      req.user?.id,
      req.user?.role,
    );
  }

  @Delete('delete')
  @UseGuards(AuthGuard)
  remove(@Query('id') id: string, @Req() req: ExpressRequest) {
    return this.eventService.remove(id, req.user?.id, req.user?.role);
  }

  @Patch('toggle-active')
  @UseGuards(AuthGuard)
  toggleActive(@Query('id') id: string, @Req() req: ExpressRequest) {
    return this.eventService.toggleActive(id, req.user?.id, req.user?.role);
  }

  @Patch('toggle-published')
  @UseGuards(AuthGuard)
  togglePublished(@Query('id') id: string, @Req() req: ExpressRequest) {
    return this.eventService.togglePublished(id, req.user?.id, req.user?.role);
  }
}
