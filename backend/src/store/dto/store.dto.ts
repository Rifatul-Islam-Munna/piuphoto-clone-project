import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsBoolean,
  IsEmail,
  IsIn,
  IsInt,
  IsMongoId,
  IsNumber,
  IsOptional,
  IsString,
  Max,
  MaxLength,
  Min,
} from 'class-validator';
export class StoreSettingsDto {
  @IsMongoId() eventId: string;
  @IsOptional() @IsBoolean() enabled?: boolean;
  @IsOptional() @IsString() @MaxLength(8) currency?: string;
  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  @Min(0)
  singlePhotoPrice?: number;
  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  @Min(0)
  wholeEventPrice?: number;
  @IsOptional() @Type(() => Number) @IsNumber() @Min(0) bundlePrice?: number;
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(2)
  @Max(500)
  bundleMinPhotos?: number;
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(720)
  downloadExpiresHours?: number;
  @IsOptional() @IsBoolean() watermarkedPreview?: boolean;
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(400)
  @Max(2400)
  previewMaxWidth?: number;
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(30)
  @Max(90)
  previewQuality?: number;
  @IsOptional() @IsBoolean() useCustomStripe?: boolean;
  @IsOptional() @IsString() @MaxLength(240) stripePublishableKey?: string;
  @IsOptional() @IsString() @MaxLength(240) stripeSecretKey?: string;
  @IsOptional() @IsString() @MaxLength(240) stripeWebhookSecret?: string;
  @IsOptional() @IsString() @MaxLength(120) stripeAccountLabel?: string;
  // Accepted for backwards compatibility with older clients. These response-only
  // flags are deliberately ignored by StoreService.updateSettings.
  @IsOptional() @IsBoolean() customStripeConfigured?: boolean;
  @IsOptional() @IsBoolean() customStripeWebhookConfigured?: boolean;
  @IsOptional()
  @IsArray()
  @ArrayMaxSize(200)
  @IsMongoId({ each: true })
  saleAlbumIds?: string[];
  @IsOptional() @IsString() @MaxLength(160) coverTitle?: string;
  @IsOptional() @IsString() @MaxLength(2000) coverImageUrl?: string;
  @IsOptional() @IsString() @MaxLength(2000) termsText?: string;
}
export class StoreAccountSettingsDto {
  @IsOptional() @IsString() @MaxLength(120) stripeAccountLabel?: string;
  @IsOptional() @IsString() @MaxLength(240) stripeSecretKey?: string;
}

export class StoreCheckoutDto {
  @IsMongoId() eventId: string;
  @IsOptional() @IsIn(['selected', 'event']) purchaseMode?:
    | 'selected'
    | 'event';
  @IsOptional()
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(1000)
  @IsMongoId({ each: true })
  imageIds?: string[];
  @IsEmail() @MaxLength(180) email: string;
  @IsOptional() @IsString() @MaxLength(40) whatsapp?: string;
  @IsOptional() @IsString() @MaxLength(120) idempotencyKey?: string;
}
export class StoreVerifyDto {
  @IsMongoId() orderId: string;
  @IsString() @MaxLength(200) sessionId: string;
}
export class StoreOrderQueryDto {
  @IsMongoId() eventId: string;
  @IsOptional() @IsString() status?: string;
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(200) limit?: number =
    100;
}

export class StoreSaleDto {
  @IsMongoId() eventId: string;
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(500)
  @IsMongoId({ each: true })
  imageIds: string[];
  @IsBoolean() isForSale: boolean;
}
