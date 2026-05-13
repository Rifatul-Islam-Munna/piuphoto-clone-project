import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import {
  IsBoolean,
  IsMongoId,
  IsNotEmpty,
  IsNumber,
  IsOptional,
  IsString,
  Min,
} from 'class-validator';

export class CreateAddonDto {
  @ApiProperty({ example: 'Extra Credits Pack' })
  @IsString()
  @IsNotEmpty()
  title: string;

  @ApiPropertyOptional({ example: 'Buy extra event processing credits' })
  @IsString()
  @IsOptional()
  description?: string;

  @ApiProperty({ example: 100 })
  @IsNumber()
  @Min(1)
  credit: number;

  @ApiProperty({ example: 19.99 })
  @IsNumber()
  @Min(0)
  price: number;

  @ApiPropertyOptional({ example: 'USD' })
  @IsString()
  @IsOptional()
  currency?: string;

  @ApiPropertyOptional({ example: 0 })
  @IsNumber()
  @IsOptional()
  order?: number;

  @ApiPropertyOptional({ example: true })
  @IsBoolean()
  @IsOptional()
  isActive?: boolean;
}

export class UpdateAddonDto {
  @ApiPropertyOptional({ example: 'Extra Credits Pack' })
  @IsString()
  @IsOptional()
  title?: string;

  @ApiPropertyOptional({ example: 'Buy extra event processing credits' })
  @IsString()
  @IsOptional()
  description?: string;

  @ApiPropertyOptional({ example: 100 })
  @IsNumber()
  @Min(1)
  @IsOptional()
  credit?: number;

  @ApiPropertyOptional({ example: 19.99 })
  @IsNumber()
  @Min(0)
  @IsOptional()
  price?: number;

  @ApiPropertyOptional({ example: 'USD' })
  @IsString()
  @IsOptional()
  currency?: string;

  @ApiPropertyOptional({ example: 0 })
  @IsNumber()
  @IsOptional()
  order?: number;

  @ApiPropertyOptional({ example: true })
  @IsBoolean()
  @IsOptional()
  isActive?: boolean;
}

export class AddonFilterDto {
  @ApiPropertyOptional({ example: 'credit' })
  @IsString()
  @IsOptional()
  query?: string;

  @ApiPropertyOptional({ example: 1, default: 1 })
  @IsOptional()
  page?: number = 1;

  @ApiPropertyOptional({ example: 10, default: 10 })
  @IsOptional()
  limit?: number = 10;

  @ApiPropertyOptional({
    example: 'all',
    enum: ['all', 'true', 'false'],
  })
  @IsString()
  @IsOptional()
  isActive?: string = 'all';
}

export class FindOneAddonDto {
  @ApiProperty({ example: '507f1f77bcf86cd799439011' })
  @IsMongoId()
  @IsNotEmpty()
  id: string;
}

export class CreateAddonCheckoutDto {
  @ApiProperty({ example: '507f1f77bcf86cd799439011' })
  @IsMongoId()
  @IsNotEmpty()
  addonId: string;
}

export class VerifyAddonCheckoutDto {
  @ApiProperty({ example: 'cs_test_123' })
  @IsString()
  @IsNotEmpty()
  sessionId: string;
}

