import { Type } from 'class-transformer';
import { ArrayMaxSize, ArrayMinSize, IsArray, IsBoolean, IsEnum, IsInt, IsMongoId, IsOptional, IsString, IsUrl, Max, MaxLength, Min } from 'class-validator';
import { RetouchJobStatus } from '../entities/retouch-job.entity';

export class RetouchListDto {
  @IsMongoId() eventId: string;
  @IsOptional() @IsEnum(RetouchJobStatus) status?: RetouchJobStatus;
  @IsOptional() @IsMongoId() albumId?: string;
  @IsOptional() @IsMongoId() photographerId?: string;
  @IsOptional() @IsMongoId() retoucherId?: string;
  @IsOptional() @IsString() @MaxLength(40) from?: string;
  @IsOptional() @IsString() @MaxLength(40) to?: string;
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(1000) limit?: number = 250;
}
export class AssignRetouchDto {
  @IsMongoId() eventId: string;
  @IsArray() @ArrayMinSize(1) @ArrayMaxSize(500) @IsMongoId({ each: true }) jobIds: string[];
  @IsMongoId() retoucherId: string;
  @IsOptional() @IsString() @MaxLength(1000) note?: string;
}
export class RetouchStatusDto {
  @IsMongoId() jobId: string;
  @IsEnum(RetouchJobStatus) status: RetouchJobStatus;
  @IsOptional() @IsString() @MaxLength(1000) note?: string;
  @IsOptional() @IsString() @MaxLength(120) deviceId?: string;
}
export class RetouchVersionDto {
  @IsMongoId() jobId: string;
  @IsUrl({ require_tld: false }) imageUrl: string;
  @IsOptional() @IsString() @MaxLength(128) checksum?: string;
  @IsOptional() @IsString() @MaxLength(1000) note?: string;
  @IsOptional() @IsString() @MaxLength(120) deviceId?: string;
}
export class ReviewRetouchDto {
  @IsMongoId() jobId: string;
  @IsEnum(['approve', 'reject']) decision: 'approve' | 'reject';
  @IsOptional() @IsString() @MaxLength(1000) reason?: string;
  @IsOptional() @IsBoolean() publish?: boolean = true;
}
export class BulkReviewRetouchDto {
  @IsArray() @ArrayMinSize(1) @ArrayMaxSize(500) @IsMongoId({ each: true }) jobIds: string[];
  @IsEnum(['approve', 'reject']) decision: 'approve' | 'reject';
  @IsOptional() @IsString() @MaxLength(1000) reason?: string;
  @IsOptional() @IsBoolean() publish?: boolean = true;
}
export class RetouchSettingsDto {
  @IsMongoId() eventId: string;
  @IsOptional() @IsBoolean() bypassReviewer?: boolean;
  @IsOptional() @IsBoolean() autoPublishApproved?: boolean;
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(12) desktopDownloadConcurrency?: number;
}
export class DesktopFeedDto {
  @IsMongoId() eventId: string;
  @IsOptional() @IsMongoId() albumId?: string;
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(500) limit?: number = 100;
}

export class UnassignRetouchDto {
  @IsMongoId() eventId: string;
  @IsArray() @ArrayMinSize(1) @ArrayMaxSize(500) @IsMongoId({ each: true }) jobIds: string[];
}
export class DesktopHeartbeatDto {
  @IsMongoId() eventId: string;
  @IsString() @MaxLength(120) deviceId: string;
}
