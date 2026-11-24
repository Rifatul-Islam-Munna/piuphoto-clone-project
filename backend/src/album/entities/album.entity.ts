import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { HydratedDocument, Types } from 'mongoose';

import { AI_PRESETS, AI_GALLERY_MODES } from '../ai-settings';
import type { AiPreset, AiGalleryMode } from '../ai-settings';

export type AlbumDocument = HydratedDocument<Album>;

@Schema({ timestamps: true, autoIndex: true })
export class Album {
  @Prop({ required: true, trim: true })
  title: string;

  @Prop({ trim: true })
  description?: string;

  @Prop({ type: Types.ObjectId, ref: 'Event', required: true, index: true })
  eventId: Types.ObjectId;

  @Prop({ type: Types.ObjectId, ref: 'User', required: true, index: true })
  userId: Types.ObjectId;

  @Prop({
    type: String,
    enum: ['inherit', 'auto_upload', 'auto_ai', 'manual'],
    default: 'inherit',
    index: true,
  })
  publishPolicy: 'inherit' | 'auto_upload' | 'auto_ai' | 'manual';

  @Prop({
    type: String,
    enum: ['inherit', 'public', 'private', 'password', 'facial'],
    default: 'inherit',
    index: true,
  })
  galleryVisibility: 'inherit' | 'public' | 'private' | 'password' | 'facial';

  @Prop({ type: Boolean })
  autoEnhanceImages?: boolean;

  @Prop({ type: String, enum: AI_PRESETS })
  aiPreset?: AiPreset;

  @Prop({ type: String, trim: true, maxlength: 1000 })
  aiPrompt?: string;

  @Prop({ type: Object })
  aiAdjustments?: import('../retouch-adjustments').RetouchAdjustments;

  @Prop({ type: String, enum: AI_GALLERY_MODES })
  aiGalleryMode?: AiGalleryMode;

  @Prop({ select: false, trim: true })
  galleryPasswordHash?: string;

  @Prop({ default: 1 })
  galleryAccessVersion: number;
}

export const AlbumSchema = SchemaFactory.createForClass(Album);

AlbumSchema.index({ eventId: 1, title: 1 });
