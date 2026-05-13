import { Controller, Get, Post, Body, Patch, Param, Delete } from '@nestjs/common';
import { WebsitesettingsService } from './websitesettings.service';
import { CreateWebsitesettingDto } from './dto/create-websitesetting.dto';
import { UpdateWebsitesettingDto } from './dto/update-websitesetting.dto';

@Controller('websitesettings')
export class WebsitesettingsController {
  constructor(private readonly websitesettingsService: WebsitesettingsService) {}

  @Post()
  create(@Body() createWebsitesettingDto: CreateWebsitesettingDto) {
    return this.websitesettingsService.create(createWebsitesettingDto);
  }

  @Get()
  findAll() {
    return this.websitesettingsService.findAll();
  }

  @Get(':id')
  findOne(@Param('id') id: string) {
    return this.websitesettingsService.findOne(+id);
  }

  @Patch(':id')
  update(@Param('id') id: string, @Body() updateWebsitesettingDto: UpdateWebsitesettingDto) {
    return this.websitesettingsService.update(+id, updateWebsitesettingDto);
  }

  @Delete(':id')
  remove(@Param('id') id: string) {
    return this.websitesettingsService.remove(+id);
  }
}
