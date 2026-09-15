import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { HydratedDocument, Types } from 'mongoose';

export type EventDocument = HydratedDocument<Event>;

@Schema({ timestamps: true, autoIndex: true, virtuals: true })
export class Event {
  @Prop({ required: true, trim: true })
  title: string;

  @Prop({ trim: true })
  description: string;

  @Prop({ type: Object })
  image?: {
    url?: string;
    publicId?: string;
  };

  @Prop({ type: Types.ObjectId, ref: 'User', required: true })
  userId: Types.ObjectId;

  @Prop({ default: true })
  isPublished: boolean;

  @Prop({ default: true })
  isActive: boolean;

  @Prop({ default: false })
  autoEnhanceImages: boolean;

  @Prop({ default: true })
  autoPublishImages: boolean;

  @Prop({ default: false })
  requireReview: boolean;

  @Prop({
    type: String,
    enum: ['auto_upload', 'auto_ai', 'manual'],
    default: 'auto_upload',
    index: true,
  })
  publishPolicy: 'auto_upload' | 'auto_ai' | 'manual';

  @Prop({
    type: String,
    enum: ['public', 'private', 'password', 'facial'],
    default: 'public',
    index: true,
  })
  galleryVisibility: 'public' | 'private' | 'password' | 'facial';

  @Prop({ select: false, trim: true })
  galleryPasswordHash?: string;

  @Prop({ default: 1 })
  galleryAccessVersion: number;

  @Prop({ default: false })
  faceSearchEnabled: boolean;

  @Prop({ default: true })
  faceConsentRequired: boolean;

  @Prop({ default: 30, min: 1, max: 365 })
  faceRetentionDays: number;

  @Prop({ default: false })
  guestNotificationsEnabled: boolean;

  @Prop({ default: true })
  emailNotificationsEnabled: boolean;

  @Prop({ default: false })
  whatsappNotificationsEnabled: boolean;

  @Prop({
    type: String,
    enum: ['off', 'hide_non_matches', 'blur_non_matches'],
    default: 'hide_non_matches',
  })
  facialPrivacyMode: 'off' | 'hide_non_matches' | 'blur_non_matches';

  @Prop({ type: Object, default: {} })
  branding?: {
    logoUrl?: string;
    coverUrl?: string;
    watermarkUrl?: string;
    watermarkPosition?: string;
    watermarkOpacity?: number;
    watermarkScale?: number;
    primaryColor?: string;
    accentColor?: string;
    fontFamily?: string;
    footerText?: string;
    sponsorText?: string;
    whiteLabel?: boolean;
  };

  @Prop({
    unique: true,
    sparse: true,
    lowercase: true,
    trim: true,
    index: true,
  })
  gallerySlug?: string;

  @Prop({ trim: true })
  customDomain?: string;

  @Prop({
    unique: true,
    sparse: true,
    trim: true,
    uppercase: true,
    index: true,
  })
  joinCode?: string;
}

export const EventSchema = SchemaFactory.createForClass(Event);
