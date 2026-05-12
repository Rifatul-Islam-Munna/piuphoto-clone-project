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
import { CreateEventDto, UpdateEventDto, EventFilterDto } from './dto/create-event.dto';
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
  @UseGuards(AuthGuard, ThrottlerGuard)
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
  getMyEvents(@Req() req: ExpressRequest) {
    return this.eventService.findAllByUser(req.user?.id);
  }

  @Get('get-all')
  findAll(@Query() query: EventFilterDto) {
    return this.eventService.findAll(query);
  }

  @Get('get-one')
  findOne(@Query('id') id: string) {
    return this.eventService.findOne(id);
  }

  @Patch('update')
  @UseGuards(AuthGuard)
  update(@Query('id') id: string, @Body() updateEventDto: UpdateEventDto) {
    return this.eventService.update(id, updateEventDto);
  }

  @Delete('delete')
  @UseGuards(AuthGuard)
  remove(@Query('id') id: string) {
    return this.eventService.remove(id);
  }

  @Patch('toggle-active')
  @UseGuards(AuthGuard)
  toggleActive(@Query('id') id: string, @Req() req: ExpressRequest) {
    return this.eventService.toggleActive(id, req.user?.id);
  }

  @Patch('toggle-published')
  @UseGuards(AuthGuard)
  togglePublished(@Query('id') id: string, @Req() req: ExpressRequest) {
    return this.eventService.togglePublished(id, req.user?.id);
  }
}
