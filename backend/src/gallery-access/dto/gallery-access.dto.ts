import { Type } from 'class-transformer';
import {
  IsBoolean,
  IsEnum,
  IsInt,
  IsMongoId,
  IsOptional,
  IsString,
  Max,
  MaxLength,
  Min,
  ValidateNested,
} from 'class-validator';

export enum GalleryAccessMode {
  INHERIT = 'inherit',
  PUBLIC = 'public',
  PRIVATE = 'private',
  PASSWORD = 'password',
  FACIAL = 'facial',
}

export enum FacialPrivacyMode {
  OFF = 'off',
  HIDE_NON_MATCHES = 'hide_non_matches',
  BLUR_NON_MATCHES = 'blur_non_matches',
}

export enum PublishPolicyMode {
  INHERIT = 'inherit',
  AUTO_UPLOAD = 'auto_upload',
  AUTO_AI = 'auto_ai',
  MANUAL = 'manual',
}

export class GalleryBrandingDto {
  @IsOptional() @IsString() @MaxLength(500) logoUrl?: string;
  @IsOptional() @IsString() @MaxLength(500) coverUrl?: string;
  @IsOptional() @IsString() @MaxLength(500) watermarkUrl?: string;
  @IsOptional() @IsString() @MaxLength(40) primaryColor?: string;
  @IsOptional() @IsString() @MaxLength(40) accentColor?: string;
  @IsOptional() @IsString() @MaxLength(80) fontFamily?: string;
  @IsOptional() @IsString() @MaxLength(180) footerText?: string;
  @IsOptional() @IsString() @MaxLength(180) sponsorText?: string;
  @IsOptional() @IsBoolean() whiteLabel?: boolean;
}

export class GallerySettingsDto {
  @IsMongoId() eventId: string;
  @IsOptional() @IsMongoId() albumId?: string;
  @IsOptional() @IsEnum(GalleryAccessMode) visibility?: GalleryAccessMode;
  @IsOptional() @IsString() @MaxLength(120) password?: string;
  @IsOptional()
  @IsEnum(FacialPrivacyMode)
  facialPrivacyMode?: FacialPrivacyMode;
  @IsOptional() @IsBoolean() faceSearchEnabled?: boolean;
  @IsOptional() @IsBoolean() faceConsentRequired?: boolean;
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(365)
  faceRetentionDays?: number;
  @IsOptional() @IsBoolean() guestNotificationsEnabled?: boolean;
  @IsOptional() @IsBoolean() emailNotificationsEnabled?: boolean;
  @IsOptional() @IsBoolean() whatsappNotificationsEnabled?: boolean;
  @IsOptional() @IsEnum(PublishPolicyMode) publishPolicy?: PublishPolicyMode;
  @IsOptional() @IsString() @MaxLength(80) gallerySlug?: string;
  @IsOptional() @IsString() @MaxLength(240) customDomain?: string;
  @IsOptional()
  @ValidateNested()
  @Type(() => GalleryBrandingDto)
  branding?: GalleryBrandingDto;
}

export class GalleryUnlockDto {
  @IsMongoId() eventId: string;
  @IsOptional() @IsMongoId() albumId?: string;
  @IsString() @MaxLength(120) password: string;
}

export class GalleryLinkDto {
  @IsMongoId() eventId: string;
  @IsOptional() @IsMongoId() albumId?: string;
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(720)
  ttlHours?: number = 72;
}
