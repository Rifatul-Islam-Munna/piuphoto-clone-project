import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsString, IsNotEmpty, IsOptional, IsBoolean, IsMongoId } from 'class-validator';

class ImageDto {
  @ApiPropertyOptional({ example: 'https://minio.example.com/bucket/image.jpg' })
  @IsString()
  @IsOptional()
  url?: string;

  @ApiPropertyOptional({ example: 'image/123' })
  @IsString()
  @IsOptional()
  publicId?: string;
}

export class CreateEventDto {
  @ApiProperty({ example: 'Community Iftar' })
  @IsString()
  @IsNotEmpty()
  title: string;

  @ApiPropertyOptional({ example: 'Join us for a community iftar gathering' })
  @IsString()
  @IsOptional()
  description?: string;

  @ApiPropertyOptional({ type: ImageDto })
  @IsOptional()
  image?: ImageDto;

  @ApiPropertyOptional({ example: '507f1f77bcf86cd799439011' })
  @IsMongoId()
  @IsOptional()
  userId: string;

  @ApiPropertyOptional({ example: true, default: true })
  @IsBoolean()
  @IsOptional()
  isPublished?: boolean;

  @ApiPropertyOptional({ example: false, default: false })
  @IsBoolean()
  @IsOptional()
  autoEnhanceImages?: boolean;
}

export class UpdateEventDto {
  @ApiPropertyOptional({ example: 'Community Iftar' })
  @IsString()
  @IsOptional()
  title?: string;

  @ApiPropertyOptional({ example: 'Join us for a community iftar gathering' })
  @IsString()
  @IsOptional()
  description?: string;

  @ApiPropertyOptional({ type: ImageDto })
  @IsOptional()
  image?: ImageDto;

  @ApiPropertyOptional({ example: true, default: true })
  @IsBoolean()
  @IsOptional()
  isPublished?: boolean;

  @ApiPropertyOptional({ example: false, default: false })
  @IsBoolean()
  @IsOptional()
  isActive?: boolean;

  @ApiPropertyOptional({ example: false, default: false })
  @IsBoolean()
  @IsOptional()
  autoEnhanceImages?: boolean;
}

export class EventFilterDto {
  @ApiPropertyOptional({ example: 'Iftar' })
  @IsOptional()
  @IsString()
  query?: string;

  @ApiPropertyOptional({ example: 1, default: 1 })
  @IsOptional()
  page?: number = 1;

  @ApiPropertyOptional({ example: 10, default: 10 })
  @IsOptional()
  limit?: number = 10;

  @ApiPropertyOptional({ example: 'true', default: 'all', enum: ['all', 'true', 'false'] })
  @IsOptional()
  @IsString()
  isPublished?: string = 'all';

  @ApiPropertyOptional({ example: 'true', default: 'all', enum: ['all', 'true', 'false'] })
  @IsOptional()
  @IsString()
  isActive?: string = 'all';
}
