import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsInt,
  IsNotEmpty,
  IsOptional,
  IsString,
  Max,
  MaxLength,
  Min,
  ValidateNested,
} from 'class-validator';

export const MAX_UPLOAD_SIZE = 256 * 1024 * 1024;

export class PresignUploadDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(255)
  fileName: string;

  @IsOptional()
  @IsString()
  @MaxLength(100)
  contentType?: string;

  @IsInt()
  @Min(1)
  @Max(MAX_UPLOAD_SIZE)
  size: number;
}

export class PresignUploadsDto {
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(100)
  @ValidateNested({ each: true })
  @Type(() => PresignUploadDto)
  files: PresignUploadDto[];
}
