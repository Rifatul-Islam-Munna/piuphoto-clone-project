import { PartialType } from '@nestjs/mapped-types';
import { CreateWebsitesettingDto } from './create-websitesetting.dto';

export class UpdateWebsitesettingDto extends PartialType(CreateWebsitesettingDto) {}
