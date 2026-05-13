import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import {
  IsBoolean,
  IsMongoId,
  IsNotEmpty,
  IsOptional,
  IsString,
  IsUrl,
} from 'class-validator';

export class CreateEventImageDto {
  @ApiProperty({ example: '507f1f77bcf86cd799439011' })
  @IsMongoId()
  @IsNotEmpty()
  eventId: string;

  @ApiProperty({ example: 'https://cdn.example.com/events/photo.jpg' })
  @IsString()
  @IsUrl({ require_tld: false })
  @IsNotEmpty()
  imageUrl: string;

  @ApiPropertyOptional({ example: 'CAM-OTP-4921' })
  @IsString()
  @IsOptional()
  referenceId?: string;

  @ApiPropertyOptional({ example: false })
  @IsBoolean()
  @IsOptional()
  isEnhanced?: boolean;
}

export class EventImageFilterDto {
  @ApiPropertyOptional({ example: '507f1f77bcf86cd799439011' })
  @IsMongoId()
  @IsOptional()
  eventId?: string;

  @ApiPropertyOptional({ example: '507f1f77bcf86cd799439012' })
  @IsMongoId()
  @IsOptional()
  userTakenBy?: string;

  @ApiPropertyOptional({ example: 'CAM-OTP-4921' })
  @IsString()
  @IsOptional()
  referenceId?: string;

  @ApiPropertyOptional({ example: false })
  @IsOptional()
  isEnhanced?: string;
}

export class EventImageQueryDto {
  @ApiProperty({ example: '507f1f77bcf86cd799439013' })
  @IsMongoId()
  @IsNotEmpty()
  id: string;
}
