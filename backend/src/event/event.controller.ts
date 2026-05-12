import {
  Controller,
  Get,
  Post,
  Patch,
  Delete,
  Body,
  Query,
  UseGuards,
} from '@nestjs/common';
import { EventService } from './event.service';
import { CreateEventDto, UpdateEventDto, EventFilterDto } from './dto/create-event.dto';
import { AuthGuard } from '../lib/auth.guard';
import { RolesGuard } from '../lib/roles.guard';
import { Roles } from '../lib/roles.decorator';
import { UserType } from '../user/entities/user.entity';
import { Throttle, ThrottlerGuard } from '@nestjs/throttler';

@Controller('event')
export class EventController {
  constructor(private readonly eventService: EventService) {}

  @Post()
  @UseGuards(AuthGuard, ThrottlerGuard)
  @Throttle({ default: { limit: 100, ttl: 3600000 } })
  create(@Body() createEventDto: CreateEventDto) {
    return this.eventService.create(createEventDto);
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
  @UseGuards(AuthGuard, RolesGuard)
  @Roles(UserType.ADMIN)
  toggleActive(@Query('id') id: string) {
    return this.eventService.toggleActive(id);
  }

  @Patch('toggle-published')
  @UseGuards(AuthGuard, RolesGuard)
  @Roles(UserType.ADMIN)
  togglePublished(@Query('id') id: string) {
    return this.eventService.togglePublished(id);
  }
}