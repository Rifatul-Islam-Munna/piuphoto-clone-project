import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import {
  IsString,
  IsEmail,
  IsBoolean,
  IsNumber,
  IsOptional,
  MinLength,
  MaxLength,
  Min,
  Max,
  IsNotEmpty,
  IsPhoneNumber,
} from 'class-validator';
import { Transform } from 'class-transformer';
import { UserType } from '../entities/user.entity';

export class CreateUserDto {
  @ApiProperty({ example: 'Ahmed Rahman', description: 'Full name of the user' })
  @IsString()
  @IsNotEmpty()
  @MinLength(3)
  @MaxLength(100)
  name: string;

  @ApiPropertyOptional({
    type: String,
    enum: UserType,
    default: UserType.USER,
  })
  @IsString()
  @IsOptional()
  role?: UserType;

  @ApiPropertyOptional({ example: '01712345678' })
  @IsString()
  @IsOptional()
  phone?: string;

  @ApiPropertyOptional({
    example: '01712345678',
    description: 'WhatsApp number used for direct WhatsApp sharing',
  })
  @IsString()
  @IsOptional()
  @Transform(({ value }) => (typeof value === 'string' ? value.trim() : value))
  whatsapp?: string;

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

  @ApiPropertyOptional({ example: 'Male', enum: ['Male', 'Female'] })
  @IsString()
  @IsOptional()
  gender?: string;

  @ApiPropertyOptional({ example: 'Never Married', enum: ['Never Married', 'Divorced', 'Widowed'] })
  @IsString()
  @IsOptional()
  maritalStatus?: string;

  @ApiPropertyOptional({ example: 25, minimum: 18, maximum: 100 })
  @IsNumber()
  @IsOptional()
  @Min(10)
  @Max(100)
  @Transform(({ value }) => parseInt(value, 10))
  age?: number;

  @ApiPropertyOptional({ example: 'A+', enum: ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'] })
  @IsString()
  @IsOptional()
  bloodGroup?: string;

  @ApiPropertyOptional({ example: 65, minimum: 30, maximum: 200, description: 'Weight in kg' })
  @IsNumber()
  @IsOptional()
  @Min(20)
  @Max(200)
  @Transform(({ value }) => parseInt(value, 10))
  weight?: number;

  @ApiPropertyOptional({ example: true, default: true })
  @IsBoolean()
  @IsOptional()
  @Transform(({ value }) => value === true || value === 'true')
  isPublished?: boolean;

  @ApiPropertyOptional({ example: false, default: false })
  @IsBoolean()
  @IsOptional()
  @Transform(({ value }) => value === true || value === 'true')
  isActive?: boolean;

  }
