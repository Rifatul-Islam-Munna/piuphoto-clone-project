import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsBoolean,
  IsIn,
  IsMongoId,
  IsOptional,
  IsString,
  MaxLength,
} from 'class-validator';

export class PublishBatchDto {
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(500)
  @IsMongoId({ each: true })
  ids: string[];
  @IsBoolean() isPublished: boolean;
}

export class EnhanceBatchDto {
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(100)
  @IsMongoId({ each: true })
  ids: string[];
  @IsOptional() @IsString() @MaxLength(1000) prompt?: string;
}

export class EnhancementJobsQueryDto {
  @IsMongoId() eventId: string;
}

export class RetryEnhancementJobDto {
  @IsMongoId() jobId: string;
}

export class AnalyzeMediaDto {
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(200)
  @IsMongoId({ each: true })
  ids: string[];
}

export class ReviewOverrideDto {
  @IsMongoId() id: string;
  @IsIn(['approve', 'reject', 'clear']) decision:
    | 'approve'
    | 'reject'
    | 'clear';
}

export class MediaSearchDto {
  @IsMongoId() eventId: string;
  @IsString() @MaxLength(200) query: string;
  @IsOptional()
  @IsIn(['all', 'face', 'number', 'semantic', 'outfit'])
  type?: string = 'all';
  @IsOptional() @Type(() => Number) limit?: number = 200;
}
