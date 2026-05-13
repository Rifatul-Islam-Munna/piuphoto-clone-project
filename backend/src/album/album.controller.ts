import { Body, Controller, Delete, Get, Patch, Post, Query, Req, UseGuards } from '@nestjs/common';
import { AlbumService } from './album.service';
import { AlbumFilterDto, AlbumQueryDto, CreateAlbumDto, UpdateAlbumDto } from './dto/album.dto';
import { AuthGuard } from '../lib/auth.guard';
import type { ExpressRequest } from '../lib/auth.guard';

@Controller('album')
export class AlbumController {
  constructor(private readonly albumService: AlbumService) {}

  @Post()
  @UseGuards(AuthGuard)
  create(@Body() dto: CreateAlbumDto, @Req() req: ExpressRequest) {
    return this.albumService.create(dto, req.user?.id, req.user?.role);
  }

  @Get('get-all')
  @UseGuards(AuthGuard)
  findAll(@Query() query: AlbumFilterDto) {
    return this.albumService.findAll(query);
  }

  @Get('public')
  findPublic(@Query('eventId') eventId: string) {
    return this.albumService.findPublicByEvent(eventId);
  }

  @Patch('update')
  @UseGuards(AuthGuard)
  update(
    @Query() query: AlbumQueryDto,
    @Body() dto: UpdateAlbumDto,
    @Req() req: ExpressRequest,
  ) {
    return this.albumService.update(query.id, dto, req.user?.id, req.user?.role);
  }

  @Delete('delete')
  @UseGuards(AuthGuard)
  remove(@Query() query: AlbumQueryDto, @Req() req: ExpressRequest) {
    return this.albumService.remove(query.id, req.user?.id, req.user?.role);
  }
}
