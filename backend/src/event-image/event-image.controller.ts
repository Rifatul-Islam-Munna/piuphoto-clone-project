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
import { Throttle, ThrottlerGuard } from '@nestjs/throttler';
import { EventImageService } from './event-image.service';
import {
  CreateEventImageDto,
  EventImageFilterDto,
  EventImageQueryDto,
} from './dto/create-event-image.dto';
import { UpdateEventImageDto } from './dto/update-event-image.dto';
import { AuthGuard } from '../lib/auth.guard';
import type { ExpressRequest } from '../lib/auth.guard';

@Controller('eventImage')
export class EventImageController {
  constructor(private readonly eventImageService: EventImageService) {}

  @Post()
  @UseGuards(AuthGuard, ThrottlerGuard)
  @Throttle({ default: { limit: 500, ttl: 3600000 } })
  create(
    @Body() createEventImageDto: CreateEventImageDto,
    @Req() req: ExpressRequest,
  ) {
    return this.eventImageService.create(
      createEventImageDto,
      req.user?.id,
      req.user?.role,
    );
  }

  @Get('get-all')
  @UseGuards(AuthGuard)
  findAll(@Query() query: EventImageFilterDto) {
    return this.eventImageService.findAll(query);
  }

  @Get('public')
  findPublic(
    @Query('eventId') eventId: string,
    @Query('albumId') albumId?: string,
  ) {
    return this.eventImageService.findPublicByEvent(eventId, albumId);
  }

  @Get('get-one')
  @UseGuards(AuthGuard)
  findOne(@Query() query: EventImageQueryDto) {
    return this.eventImageService.findOne(query.id);
  }

  @Patch('update')
  @UseGuards(AuthGuard)
  update(
    @Query() query: EventImageQueryDto,
    @Body() updateEventImageDto: UpdateEventImageDto,
    @Req() req: ExpressRequest,
  ) {
    return this.eventImageService.update(
      query.id,
      updateEventImageDto,
      req.user?.id,
      req.user?.role,
    );
  }

  @Delete('delete')
  @UseGuards(AuthGuard)
  remove(@Query() query: EventImageQueryDto, @Req() req: ExpressRequest) {
    return this.eventImageService.remove(query.id, req.user?.id, req.user?.role);
  }
}
