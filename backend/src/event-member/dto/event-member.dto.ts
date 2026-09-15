import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Transform } from 'class-transformer';
import {
  IsArray,
  IsBoolean,
  IsEnum,
  IsMongoId,
  IsOptional,
  IsString,
  Length,
} from 'class-validator';
import { EventMemberRole } from '../entities/event-member.entity';

export class AddEventMemberDto {
  @ApiProperty()
  @IsMongoId()
  eventId: string;

  @ApiProperty()
  @IsMongoId()
  userId: string;

  @ApiProperty({ enum: EventMemberRole })
  @IsEnum(EventMemberRole)
  role: EventMemberRole;

  @ApiPropertyOptional({ type: [String] })
  @IsArray()
  @IsMongoId({ each: true })
  @IsOptional()
  assignedAlbumIds?: string[];

  @ApiPropertyOptional({ default: false })
  @IsBoolean()
  @IsOptional()
  @Transform(({ value }) => value === true || value === 'true')
  canPublish?: boolean;
}

export class UpdateEventMemberDto {
  @ApiPropertyOptional({ enum: EventMemberRole })
  @IsEnum(EventMemberRole)
  @IsOptional()
  role?: EventMemberRole;

  @ApiPropertyOptional({ type: [String] })
  @IsArray()
  @IsMongoId({ each: true })
  @IsOptional()
  assignedAlbumIds?: string[];

  @ApiPropertyOptional()
  @IsBoolean()
  @IsOptional()
  @Transform(({ value }) => value === true || value === 'true')
  canPublish?: boolean;
}

export class JoinEventByCodeDto {
  @ApiProperty({ example: 'A1B2C3D4E5' })
  @IsString()
  @Length(6, 32)
  @Transform(({ value }) =>
    String(value ?? '')
      .trim()
      .toUpperCase(),
  )
  code: string;
}
