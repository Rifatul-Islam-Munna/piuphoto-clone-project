import { ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { RetouchAdjustmentsDto } from './retouch-adjustments.dto';
import { IsBoolean, IsIn, IsObject, IsOptional, IsString, MaxLength, ValidateNested } from 'class-validator';
import { AI_PRESETS, AI_GALLERY_MODES } from './ai-settings';
import type { AiPreset, AiGalleryMode } from './ai-settings';

// Null explicitly clears an album override and restores event defaults.
export class AiSettingsDto {
  @ApiPropertyOptional({ type: Boolean, nullable: true })
  @IsOptional()
  @IsBoolean()
  autoEnhanceImages?: boolean | null;

  @ApiPropertyOptional({ enum: AI_PRESETS, nullable: true })
  @IsOptional()
  @IsIn(AI_PRESETS)
  aiPreset?: AiPreset | null;

  @ApiPropertyOptional({ maxLength: 1000, nullable: true })
  @IsOptional()
  @IsString()
  @MaxLength(1000)
  aiPrompt?: string | null;

  @ApiPropertyOptional({ type: RetouchAdjustmentsDto, nullable: true })
  @IsOptional()
  @IsObject()
  @ValidateNested()
  @Type(() => RetouchAdjustmentsDto)
  aiAdjustments?: RetouchAdjustmentsDto | null;

  @ApiPropertyOptional({ enum: AI_GALLERY_MODES, nullable: true })
  @IsOptional()
  @IsIn(AI_GALLERY_MODES)
  aiGalleryMode?: AiGalleryMode | null;
}
