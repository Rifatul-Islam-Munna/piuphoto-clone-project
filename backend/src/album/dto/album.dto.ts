import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsMongoId, IsNotEmpty, IsOptional, IsString } from 'class-validator';

import { AiSettingsDto } from '../ai-settings.dto';

export class CreateAlbumDto extends AiSettingsDto {
  @ApiProperty({ example: 'Wedding Highlights' })
  @IsString()
  @IsNotEmpty()
  title: string;

  @ApiPropertyOptional({ example: 'Best ceremony photos' })
  @IsString()
  @IsOptional()
  description?: string;

  @ApiProperty({ example: '507f1f77bcf86cd799439011' })
  @IsMongoId()
  @IsNotEmpty()
  eventId: string;
}

export class UpdateAlbumDto extends AiSettingsDto {
  @ApiPropertyOptional({ example: 'Wedding Highlights' })
  @IsString()
  @IsOptional()
  title?: string;

  @ApiPropertyOptional({ example: 'Best ceremony photos' })
  @IsString()
  @IsOptional()
  description?: string;
}

export class AlbumQueryDto {
  @ApiProperty({ example: '507f1f77bcf86cd799439011' })
  @IsMongoId()
  @IsNotEmpty()
  id: string;
}

export class AlbumFilterDto {
  @ApiPropertyOptional({ example: '507f1f77bcf86cd799439011' })
  @IsMongoId()
  @IsOptional()
  eventId?: string;
}
