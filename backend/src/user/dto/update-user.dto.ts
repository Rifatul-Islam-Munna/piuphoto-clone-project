import { ApiProperty, ApiPropertyOptional, PartialType } from '@nestjs/swagger';
import { UserType } from '../entities/user.entity';
import { CreateUserDto } from './create-user.dto';
import {
  IsArray,
  IsEmail,
  IsInt,
  IsMongoId,
  IsNotEmpty,
  IsNumber,
  IsOptional,
  IsPhoneNumber,
  IsString,
  Matches,
  Max,
  MaxLength,
  Min,
  MinLength,
} from 'class-validator';
import { Transform, Type } from 'class-transformer';

export class UpdateUserDto extends PartialType(CreateUserDto) {
  @ApiProperty({ example: '507f1f77bcf86cd799439011' })
  @IsMongoId()
  @IsOptional()
  id?: string;

  @ApiPropertyOptional()
  @IsOptional()
  _v?: string;

  @ApiPropertyOptional()
  @IsOptional()
  updatedAt?: string;

  @ApiPropertyOptional()
  @IsOptional()
  createdAt?: string;

  @ApiPropertyOptional({ example: 5 })
  @Transform(({ value }) => (value ? parseInt(value, 10) : undefined))
  @IsInt()
  @IsOptional()
  numberOfConnections?: number;

  @ApiPropertyOptional({ example: '507f1f77bcf86cd799439011' })
  @IsMongoId()
  @IsOptional()
  plan_reference?: string;

  @ApiPropertyOptional({ example: '2024-01-01' })
  @IsOptional()
  @Transform(({ value }) => (value ? new Date(value) : undefined))
  subscription_starting_date?: Date;

  @ApiPropertyOptional({ example: '2025-01-01' })
  @IsOptional()
  @Transform(({ value }) => (value ? new Date(value) : undefined))
  subscription_end_date?: Date;

  @ApiPropertyOptional()
  @IsOptional()
  profileImage?: { url: string; key: string };
}

export class LoginDto {
  @ApiProperty({ example: 'ahmed@example.com' })
  @IsEmail()
  @IsNotEmpty()
  @Transform(({ value }) => (value ? value.toLowerCase().trim() : undefined))
  email: string;

  @ApiProperty({ example: 'StrongPass@123', minLength: 8 })
  @IsString()
  @IsNotEmpty()
  @MinLength(7)
  @MaxLength(50)
  password: string;
}

export class UserFilterDto {
  @ApiPropertyOptional({
    description: 'Search term for name (fuzzy search)',
    example: 'John',
  })
  @IsOptional()
  @IsString()
  @Transform(({ value }) => value?.trim())
  query?: string;

  @ApiPropertyOptional({
    description: 'Page number for pagination',
    example: 1,
    default: 1,
  })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  page?: number = 1;

  @ApiPropertyOptional({
    description: 'Users per page',
    example: 10,
    default: 10,
  })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(200)
  limit?: number = 10;

  @ApiPropertyOptional({
    description: 'Gender filter',
    example: 'male',
    default: 'all',
    enum: ['all', 'male', 'female'],
  })
  @IsOptional()
  @IsString()
  gender?: string = 'all';

  @ApiPropertyOptional({
    description: 'Marital status filter (comma-separated)',
    example: 'single,divorced',
    isArray: true,
    type: String,
  })
  @IsOptional()
  @Transform(({ value }) => {
    if (Array.isArray(value)) return value;
    return value ? value.split(',').map((v: string) => v.trim()) : [];
  })
  @IsArray()
  maritalStatus?: string[];

  @ApiPropertyOptional({
    description: 'Role filter (comma-separated)',
    example: 'user,photographer',
    isArray: true,
    type: String,
  })
  @IsOptional()
  @Transform(({ value }) => {
    if (Array.isArray(value)) return value;
    return value ? value.split(',').map((v: string) => v.trim()) : [];
  })
  @IsArray()
  role?: string[];

  @ApiPropertyOptional({
    description: 'Minimum age',
    example: 18,
  })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(10)
  ageMin?: number;

  @ApiPropertyOptional({
    description: 'Maximum age',
    example: 40,
  })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Max(100)
  ageMax?: number;

  @ApiPropertyOptional({
    description: 'Active filter (true/false)',
    example: 'true',
    default: 'all',
    enum: ['all', 'true', 'false'],
  })
  @IsOptional()
  @IsString()
  isActive?: string = 'all';
}

export class FindOneQueryDto {
  @ApiProperty({ example: '507f1f77bcf86cd799439011' })
  @IsString()
  @IsNotEmpty()
  id: string;
}

export class FindOneByFieldDto {
  @ApiProperty({ example: 'john@example.com' })
  @IsString()
  @IsNotEmpty()
  field: string;

  @ApiProperty({ example: 'email' })
  @IsString()
  @IsNotEmpty()
  value: string;
}

export class ResetPasswordDto {
  @ApiProperty({ example: 'oldPassword123' })
  @IsString()
  oldPassword: string;

  @ApiProperty({ example: 'newPassword456' })
  @IsString()
  @MinLength(7)
  @MaxLength(50)
  newPassword: string;
}

export class AdminUserDto {
  @ApiPropertyOptional({
    description: 'Search term for name (fuzzy search)',
    example: 'John',
  })
  @IsOptional()
  @IsString()
  @Transform(({ value }) => value?.trim())
  query?: string;

  @ApiPropertyOptional({
    description: 'Page number for pagination',
    example: 1,
    default: 1,
  })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  page?: number = 1;

  @ApiPropertyOptional({
    description: 'Users per page',
    example: 100,
    default: 10,
  })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(200)
  limit?: number = 10;

  @ApiPropertyOptional({
    description: 'Gender filter',
    example: 'male',
    default: 'all',
    enum: ['all', 'male', 'female'],
  })
  @IsOptional()
  @IsString()
  gender?: string = 'all';

  @ApiPropertyOptional({
    description: 'Published filter',
    example: 'published',
    default: 'all',
    enum: ['all', 'true', 'false'],
  })
  @IsOptional()
  @IsString()
  isPublished?: string = 'all';

  @ApiPropertyOptional({
    description: 'Active filter',
    example: 'true',
    default: 'all',
    enum: ['all', 'true', 'false'],
  })
  @IsOptional()
  @IsString()
  isActive?: string = 'all';
}

export class OtpVerifyDto {
  @ApiProperty({ example: '123456' })
  @IsString()
  @IsNotEmpty()
  otp: string;
}

export class ReqForOtpDto {
  @ApiProperty({ example: '01712345678' })
  @IsPhoneNumber('BD')
  phone: string;
}

export class ResetPasswordWithOtpDto {
  @ApiProperty({ example: '01712345678' })
  @IsPhoneNumber('BD')
  phone: string;

  @ApiProperty({ example: '123456' })
  @IsString()
  @IsNotEmpty()
  otp: string;

  @ApiProperty({ example: 'newPassword123' })
  @IsString()
  @IsNotEmpty()
  @MinLength(7)
  @MaxLength(50)
  newPassword: string;
}

export class ChangeRoleDto {
  @ApiProperty({ example: '507f1f77bcf86cd799439011' })
  @IsMongoId()
  @IsNotEmpty()
  userId: string;

  @ApiProperty({ enum: UserType })
  @IsString()
  @IsNotEmpty()
  role: string;
}

export { UserType };
export { CreateUserDto } from './create-user.dto';
