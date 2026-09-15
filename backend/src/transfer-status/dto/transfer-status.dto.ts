import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  IsEnum,
  IsInt,
  IsIn,
  IsMongoId,
  IsNumber,
  IsOptional,
  IsString,
  Max,
  Min,
} from 'class-validator';
import { PhotoTransferState } from '../entities/photo-transfer-status.entity';

export class UpsertTransferStatusDto {
  @ApiProperty()
  @IsMongoId()
  eventId: string;

  @ApiProperty()
  @IsString()
  clientTransferId: string;

  @ApiProperty()
  @IsString()
  filename: string;

  @ApiPropertyOptional({ default: 'camera' })
  @IsString()
  @IsOptional()
  source?: string;

  @ApiPropertyOptional()
  @IsString()
  @IsOptional()
  cameraId?: string;

  @ApiPropertyOptional({ enum: ['photo', 'video'] })
  @IsIn(['photo', 'video'])
  @IsOptional()
  mediaType?: 'photo' | 'video';

  @ApiPropertyOptional()
  @IsMongoId()
  @IsOptional()
  albumId?: string;

  @ApiProperty({ enum: PhotoTransferState })
  @IsEnum(PhotoTransferState)
  status: PhotoTransferState;

  @ApiPropertyOptional({ minimum: 0, maximum: 100 })
  @Type(() => Number)
  @IsInt()
  @Min(0)
  @Max(100)
  @IsOptional()
  progress?: number;

  @ApiPropertyOptional({ minimum: 0 })
  @Type(() => Number)
  @IsInt()
  @Min(0)
  @IsOptional()
  bytesSent?: number;

  @ApiPropertyOptional({ minimum: 0 })
  @Type(() => Number)
  @IsInt()
  @Min(0)
  @IsOptional()
  bytesTotal?: number;

  @ApiPropertyOptional({ minimum: 0 })
  @Type(() => Number)
  @IsNumber()
  @Min(0)
  @IsOptional()
  bytesPerSecond?: number;

  @ApiPropertyOptional()
  @IsString()
  @IsOptional()
  error?: string;

  @ApiPropertyOptional()
  @IsString()
  @IsOptional()
  imageUrl?: string;

  @ApiPropertyOptional()
  @IsMongoId()
  @IsOptional()
  eventImageId?: string;
}

export class TransferStatusQueryDto {
  @ApiProperty()
  @IsMongoId()
  eventId: string;

  @ApiPropertyOptional({ enum: PhotoTransferState })
  @IsEnum(PhotoTransferState)
  @IsOptional()
  status?: PhotoTransferState;

  @ApiPropertyOptional({ default: 200, maximum: 1000 })
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(1000)
  @IsOptional()
  limit?: number = 200;
}
