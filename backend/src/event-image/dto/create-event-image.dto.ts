import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsBoolean,
  IsNumberString,
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

  @ApiPropertyOptional({ example: false })
  @IsBoolean()
  @IsOptional()
  isEnhanced?: boolean;

  @ApiPropertyOptional({ example: '507f1f77bcf86cd799439014' })
  @IsMongoId()
  @IsOptional()
  albumId?: string;

  @ApiPropertyOptional({ example: 'Make lighting warm and cinematic' })
  @IsString()
  @IsOptional()
  enhancePrompt?: string;
}

export class CreateEventImagesBatchDto {
  @ApiProperty({ example: '507f1f77bcf86cd799439011' })
  @IsMongoId()
  @IsNotEmpty()
  eventId: string;

  @ApiProperty({
    example: ['https://cdn.example.com/events/photo-1.jpg'],
    type: [String],
  })
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(100)
  @IsUrl({ require_tld: false }, { each: true })
  imageUrls: string[];

  @ApiPropertyOptional({ example: false })
  @IsBoolean()
  @IsOptional()
  isEnhanced?: boolean;

  @ApiPropertyOptional({ example: '507f1f77bcf86cd799439014' })
  @IsMongoId()
  @IsOptional()
  albumId?: string;

  @ApiPropertyOptional({ example: 'Make lighting warm and cinematic' })
  @IsString()
  @IsOptional()
  enhancePrompt?: string;
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

  @ApiPropertyOptional({ example: false })
  @IsOptional()
  isEnhanced?: string;

  @ApiPropertyOptional({ example: '507f1f77bcf86cd799439014' })
  @IsMongoId()
  @IsOptional()
  albumId?: string;

  @ApiPropertyOptional({ example: 1 })
  @IsNumberString()
  @IsOptional()
  page?: string;

  @ApiPropertyOptional({ example: 20 })
  @IsNumberString()
  @IsOptional()
  limit?: string;
}

export class EventImageQueryDto {
  @ApiProperty({ example: '507f1f77bcf86cd799439013' })
  @IsMongoId()
  @IsNotEmpty()
  id: string;
}

export class EnhanceEventImageDto {
  @ApiProperty({ example: '507f1f77bcf86cd799439013' })
  @IsMongoId()
  @IsNotEmpty()
  id: string;

  @ApiPropertyOptional({ example: 'Make it bright and natural' })
  @IsString()
  @IsOptional()
  prompt?: string;
}
