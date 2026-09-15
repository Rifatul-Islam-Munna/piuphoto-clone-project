import { Type } from 'class-transformer';
import { IsIn, IsMongoId, IsOptional, IsString, MaxLength } from 'class-validator';
const types=['gallery_visit','image_view','download','share','face_search','notification_open','notification_click','store_view','store_checkout'] as const;
export class TrackAnalyticsDto {
  @IsMongoId() eventId:string;
  @IsOptional() @IsMongoId() imageId?:string;
  @IsOptional() @IsMongoId() albumId?:string;
  @IsString() @IsIn(types) type:typeof types[number];
  @IsOptional() @IsString() @MaxLength(40) channel?:string;
}
export class AnalyticsSummaryDto {
  @IsMongoId() eventId:string;
  @IsOptional() @IsString() from?:string;
  @IsOptional() @IsString() to?:string;
  @IsOptional() @IsMongoId() albumId?:string;
  @IsOptional() @IsMongoId() photographerId?:string;
  @IsOptional() @IsString() @MaxLength(40) channel?:string;
}
