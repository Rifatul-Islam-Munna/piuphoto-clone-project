import { Type } from 'class-transformer';
import { IsInt, IsObject, IsOptional, Max, Min, ValidateNested } from 'class-validator';
import type { RetouchAdjustments } from './retouch-adjustments';

export class PhotoAdjustmentsDto {
  @IsOptional() @IsInt() @Min(0) @Max(100)
  exposure?: number;

  @IsOptional() @IsInt() @Min(0) @Max(100)
  highlights?: number;

  @IsOptional() @IsInt() @Min(0) @Max(100)
  shadows?: number;

  @IsOptional() @IsInt() @Min(0) @Max(100)
  whiteBalance?: number;

  @IsOptional() @IsInt() @Min(0) @Max(100)
  contrast?: number;

  @IsOptional() @IsInt() @Min(0) @Max(100)
  color?: number;

  @IsOptional() @IsInt() @Min(0) @Max(100)
  noise?: number;

  @IsOptional() @IsInt() @Min(0) @Max(100)
  sharpness?: number;

  @IsOptional() @IsInt() @Min(0) @Max(100)
  deblur?: number;

  @IsOptional() @IsInt() @Min(0) @Max(100)
  haze?: number;
}

export class AdultPortraitAdjustmentsDto {
  @IsOptional() @IsInt() @Min(0) @Max(40)
  blemish?: number;

  @IsOptional() @IsInt() @Min(0) @Max(25)
  forehead?: number;

  @IsOptional() @IsInt() @Min(0) @Max(25)
  eyeWrinkle?: number;

  @IsOptional() @IsInt() @Min(0) @Max(30)
  underEye?: number;

  @IsOptional() @IsInt() @Min(0) @Max(20)
  texture?: number;
}

export class ChildPortraitAdjustmentsDto {
  @IsOptional() @IsInt() @Min(0) @Max(15)
  blemish?: number;
}

export class RetouchAdjustmentsDto implements RetouchAdjustments {
  @IsOptional() @IsObject() @ValidateNested() @Type(() => PhotoAdjustmentsDto)
  photo?: PhotoAdjustmentsDto;

  @IsOptional() @IsObject() @ValidateNested() @Type(() => AdultPortraitAdjustmentsDto)
  male?: AdultPortraitAdjustmentsDto;

  @IsOptional() @IsObject() @ValidateNested() @Type(() => AdultPortraitAdjustmentsDto)
  female?: AdultPortraitAdjustmentsDto;

  @IsOptional() @IsObject() @ValidateNested() @Type(() => ChildPortraitAdjustmentsDto)
  child?: ChildPortraitAdjustmentsDto;
}
