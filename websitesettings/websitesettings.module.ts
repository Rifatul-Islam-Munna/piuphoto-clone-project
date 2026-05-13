import { Module } from '@nestjs/common';
import { WebsitesettingsService } from './websitesettings.service';
import { WebsitesettingsController } from './websitesettings.controller';

@Module({
  controllers: [WebsitesettingsController],
  providers: [WebsitesettingsService],
})
export class WebsitesettingsModule {}
