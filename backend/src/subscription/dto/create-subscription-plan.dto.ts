import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import {
  IsString,
  IsNumber,
  IsOptional,
  IsBoolean,
  IsArray,
  IsEnum,
  Min,
} from 'class-validator';
import { BillingUnit } from '../entities/subscription-plan.entity';

export class CreateSubscriptionPlanDto {
  @ApiProperty({ example: 'Premium Plan' })
  @IsString()
  @IsOptional()
  title?: string;

  @ApiPropertyOptional({ example: 'Get unlimited access' })
  @IsString()
  @IsOptional()
  description?: string;

  @ApiProperty({ example: 99 })
  @IsNumber()
  @Min(0)
  price: number;

  @ApiPropertyOptional({ example: 79 })
  @IsNumber()
  @Min(0)
  @IsOptional()
  discount_price?: number;

  @ApiPropertyOptional({ example: [] })
  @IsArray()
  @IsOptional()
  permissions?: Record<string, unknown>[];

  @ApiPropertyOptional({ example: ['Feature 1', 'Feature 2'] })
  @IsArray()
  @IsOptional()
  features?: string[];

  @ApiPropertyOptional({ example: 1 })
  @IsNumber()
  @IsOptional()
  order?: number;

  @ApiPropertyOptional({ example: true })
  @IsBoolean()
  @IsOptional()
  isPopular?: boolean;

  @ApiPropertyOptional({ example: 'USD' })
  @IsString()
  @IsOptional()
  currency?: string;

  @ApiPropertyOptional({ enum: BillingUnit, default: BillingUnit.PER_MONTH })
  @IsEnum(BillingUnit)
  @IsOptional()
  billingUnit?: BillingUnit;

  @ApiPropertyOptional({ example: true })
  @IsBoolean()
  @IsOptional()
  isActive?: boolean;
}

export class UpdateSubscriptionPlanDto {
  @ApiPropertyOptional({ example: 'Premium Plan' })
  @IsString()
  @IsOptional()
  title?: string;

  @ApiPropertyOptional({ example: 'Get unlimited access' })
  @IsString()
  @IsOptional()
  description?: string;

  @ApiPropertyOptional({ example: 99 })
  @IsNumber()
  @Min(0)
  @IsOptional()
  price?: number;

  @ApiPropertyOptional({ example: 79 })
  @IsNumber()
  @Min(0)
  @IsOptional()
  discount_price?: number;

  @ApiPropertyOptional({ example: [] })
  @IsArray()
  @IsOptional()
  permissions?: Record<string, unknown>[];

  @ApiPropertyOptional({ example: ['Feature 1', 'Feature 2'] })
  @IsArray()
  @IsOptional()
  features?: string[];

  @ApiPropertyOptional({ example: 1 })
  @IsNumber()
  @IsOptional()
  order?: number;

  @ApiPropertyOptional({ example: true })
  @IsBoolean()
  @IsOptional()
  isPopular?: boolean;

  @ApiPropertyOptional({ example: 'USD' })
  @IsString()
  @IsOptional()
  currency?: string;

  @ApiPropertyOptional({ enum: BillingUnit })
  @IsEnum(BillingUnit)
  @IsOptional()
  billingUnit?: BillingUnit;

  @ApiPropertyOptional({ example: true })
  @IsBoolean()
  @IsOptional()
  isActive?: boolean;
}

export class SubscriptionPlanFilterDto {
  @ApiPropertyOptional({ description: 'Page number', example: 1, default: 1 })
  @IsNumber()
  @IsOptional()
  page?: number = 1;

  @ApiPropertyOptional({ description: 'Items per page', example: 10, default: 10 })
  @IsNumber()
  @IsOptional()
  limit?: number = 10;

  @ApiPropertyOptional({
    description: 'Filter by billing unit',
    enum: BillingUnit,
  })
  @IsEnum(BillingUnit)
  @IsOptional()
  billingUnit?: BillingUnit;

  @ApiPropertyOptional({
    description: 'Filter by active status (true/false)',
    example: 'true',
    enum: ['true', 'false'],
  })
  @IsString()
  @IsOptional()
  isActive?: string = 'true';

  @ApiPropertyOptional({
    description: 'Show only popular plans',
    example: 'true',
    enum: ['true', 'false'],
  })
  @IsString()
  @IsOptional()
  isPopular?: string;

  @ApiPropertyOptional({
    description: 'Search by title',
    example: 'Premium',
  })
  @IsString()
  @IsOptional()
  query?: string;
}

export class FindOnePlanDto {
  @ApiProperty({ example: '507f1f77bcf86cd799439011' })
  @IsString()
  id: string;
}

export class CreateSubscriptionCheckoutDto {
  @ApiProperty({ example: '507f1f77bcf86cd799439011' })
  @IsString()
  id: string;
}

export class VerifySubscriptionCheckoutDto {
  @ApiProperty({ example: 'cs_test_123' })
  @IsString()
  sessionId: string;
}

export class PurchaseHistoryFilterDto {
  @ApiPropertyOptional({ enum: ['all', 'plan', 'addon'], default: 'all' })
  @IsString()
  @IsOptional()
  type?: string = 'all';
}

export class InvoiceQueryDto {
  @ApiProperty({ example: '507f1f77bcf86cd799439011' })
  @IsString()
  id: string;

  @ApiProperty({ enum: ['plan', 'addon'] })
  @IsString()
  type: string;
}
