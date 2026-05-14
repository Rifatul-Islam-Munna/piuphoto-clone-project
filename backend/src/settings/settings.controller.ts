import { Controller, Get, Post, Body, Patch, UseGuards } from '@nestjs/common';
import { SettingsService } from './settings.service';
import { CreateSettingDto } from './dto/create-setting.dto';
import { UpdateSettingDto } from './dto/update-setting.dto';
import { AuthGuard } from '../lib/auth.guard';
import { RolesGuard } from '../lib/roles.guard';
import { Roles } from '../lib/roles.decorator';
import { UserType } from '../user/entities/user.entity';

@Controller('settings')
export class SettingsController {
  constructor(private readonly settingsService: SettingsService) {}

  @Post()
  @UseGuards(AuthGuard, RolesGuard)
  @Roles(UserType.ADMIN)
  create(@Body() createSettingDto: CreateSettingDto) {
    return this.settingsService.create(createSettingDto);
  }

  @Get('public')
  getPublicSettings() {
    return this.settingsService.getPublicSettings();
  }

  @Get('admin')
  @UseGuards(AuthGuard, RolesGuard)
  @Roles(UserType.ADMIN)
  getAdminSettings() {
    return this.settingsService.getAdminSettings();
  }

  @Patch('admin')
  @UseGuards(AuthGuard, RolesGuard)
  @Roles(UserType.ADMIN)
  updateSettings(@Body() updateSettingDto: UpdateSettingDto) {
    return this.settingsService.updateWebsiteSettings(updateSettingDto);
  }
}
