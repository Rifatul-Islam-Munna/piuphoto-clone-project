import { OmitType } from '@nestjs/swagger';
import {
  ArrayMaxSize, ArrayMinSize, IsArray, IsBoolean, IsIn, IsMongoId,
  IsOptional, IsString, IsUrl, MaxLength,
} from 'class-validator';
import { CreateAlbumDto, UpdateAlbumDto } from '../../album/dto/album.dto';
import { GallerySettingsDto } from '../../gallery-access/dto/gallery-access.dto';

export const apiScopes=['setup:read','setup:write','viewer:read','upload:write','ai:read','ai:write','analytics:read','webhooks:write'] as const;
export class CreateApiKeyDto {
  @IsString() @MaxLength(80) name:string;
  @IsArray() @ArrayMaxSize(20) @IsIn(apiScopes,{each:true}) scopes:string[];
  @IsOptional() @IsArray() @ArrayMaxSize(100) @IsMongoId({each:true}) eventIds?:string[];
}
export class RevokeApiKeyDto { @IsMongoId() id:string; }
export class CreateApiWebhookDto {
  @IsMongoId() eventId:string;
  @IsUrl({require_tld:false}) url:string;
  @IsOptional() @IsArray() @ArrayMaxSize(20) @IsString({each:true}) eventTypes?:string[];
}
export class DeleteApiWebhookDto { @IsMongoId() id:string; }

export class ApiCreateCategoryDto extends OmitType(CreateAlbumDto, ['eventId'] as const) {}
export class ApiUpdateCategoryDto extends UpdateAlbumDto {}
export class ApiGallerySettingsDto extends OmitType(
  GallerySettingsDto,
  ['eventId', 'albumId'] as const,
) {}
export class ApiCreateEventDto {
  @IsString() @MaxLength(160) title:string;
  @IsOptional() @IsString() @MaxLength(2000) description?:string;
  @IsOptional() @IsBoolean() isPublished?:boolean;
}
export class ApiUpdateEventDto {
  @IsOptional() @IsString() @MaxLength(160) title?:string;
  @IsOptional() @IsString() @MaxLength(2000) description?:string;
  @IsOptional() @IsBoolean() isPublished?:boolean;
  @IsOptional() @IsBoolean() isActive?:boolean;
}
export class ApiUploadDto {
  @IsMongoId() eventId:string;
  @IsOptional() @IsMongoId() albumId?:string;
  @IsUrl({require_tld:false}) imageUrl:string;
  @IsString() @MaxLength(180) idempotencyKey:string;
  @IsOptional() @IsIn(['photo','video']) mediaType?:'photo'|'video';
}
export class ApiUploadFileDto extends OmitType(ApiUploadDto, ['imageUrl'] as const) {}
export class ApiAnalyzeDto {
  @IsMongoId() eventId:string;
  @IsArray() @ArrayMinSize(1) @ArrayMaxSize(500) @IsMongoId({each:true}) ids:string[];
}
export class ApiEnhanceDto {
  @IsMongoId() eventId:string;
  @IsMongoId() imageId:string;
  @IsOptional() @IsString() @MaxLength(1000) prompt?:string;
}
export class ApiFaceSearchDto {
  @IsMongoId() eventId:string;
  @IsOptional() @IsMongoId() albumId?:string;
}
export class ApiMobileSearchDto {
  @IsMongoId() eventId:string;
  @IsString() @MaxLength(40) mobile:string;
  @IsOptional() @IsMongoId() albumId?:string;
}
