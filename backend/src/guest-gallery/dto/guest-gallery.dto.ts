import { Transform } from 'class-transformer';
import {
  IsBoolean,
  IsEmail,
  IsMongoId,
  IsOptional,
  IsString,
  MaxLength,
} from 'class-validator';

const boolValue = ({ value }: { value: unknown }) =>
  value === true || value === 'true' || value === '1';

export class RegisterGuestDto {
  @IsMongoId() eventId: string;
  @IsOptional() @IsMongoId() albumId?: string;
  @IsOptional() @IsEmail() @MaxLength(180) email?: string;
  @IsOptional() @IsString() @MaxLength(40) whatsapp?: string;
  @Transform(boolValue) @IsBoolean() consent: boolean;
  @IsOptional() @Transform(boolValue) @IsBoolean() notifyEmail?: boolean;
  @IsOptional() @Transform(boolValue) @IsBoolean() notifyWhatsapp?: boolean;
  @IsOptional() @IsString() @MaxLength(2000) accessToken?: string;
}

export class PersonalGalleryQueryDto {
  @IsMongoId() eventId: string;
  @IsOptional() @IsMongoId() albumId?: string;
  @IsString() @MaxLength(2000) guestToken: string;
}

export class DeleteGuestDto {
  @IsMongoId() eventId: string;
  @IsString() @MaxLength(2000) guestToken: string;
}

export class UpdateGuestPreferencesDto {
  @IsMongoId() eventId: string;
  @IsString() @MaxLength(2000) guestToken: string;
  @IsOptional() @IsEmail() @MaxLength(180) email?: string;
  @IsOptional() @IsString() @MaxLength(40) whatsapp?: string;
  @IsOptional() @Transform(boolValue) @IsBoolean() notifyEmail?: boolean;
  @IsOptional() @Transform(boolValue) @IsBoolean() notifyWhatsapp?: boolean;
}
