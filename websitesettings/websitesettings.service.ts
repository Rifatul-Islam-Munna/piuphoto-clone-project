import { Injectable } from '@nestjs/common';
import { CreateWebsitesettingDto } from './dto/create-websitesetting.dto';
import { UpdateWebsitesettingDto } from './dto/update-websitesetting.dto';

@Injectable()
export class WebsitesettingsService {
  create(createWebsitesettingDto: CreateWebsitesettingDto) {
    return 'This action adds a new websitesetting';
  }

  findAll() {
    return `This action returns all websitesettings`;
  }

  findOne(id: number) {
    return `This action returns a #${id} websitesetting`;
  }

  update(id: number, updateWebsitesettingDto: UpdateWebsitesettingDto) {
    return `This action updates a #${id} websitesetting`;
  }

  remove(id: number) {
    return `This action removes a #${id} websitesetting`;
  }
}
