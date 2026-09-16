import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { HydratedDocument, Types } from 'mongoose';
export type StoreSettingsDocument = HydratedDocument<StoreSettings>;
@Schema({ timestamps: true })
export class StoreSettings {
  @Prop({
    type: Types.ObjectId,
    ref: 'Event',
    required: true,
    unique: true,
    index: true,
  })
  eventId: Types.ObjectId;
  @Prop({ default: false, index: true }) enabled: boolean;
  @Prop({ trim: true, uppercase: true, default: 'USD' }) currency: string;
  @Prop({ default: 5, min: 0 }) singlePhotoPrice: number;
  @Prop({ default: 0, min: 0 }) wholeEventPrice: number;
  @Prop({ default: 0, min: 0 }) bundlePrice: number;
  @Prop({ default: 10, min: 2 }) bundleMinPhotos: number;
  @Prop({ default: 72, min: 1, max: 720 }) downloadExpiresHours: number;
  @Prop({ default: true }) watermarkedPreview: boolean;
  @Prop({ default: 1200, min: 400, max: 2400 }) previewMaxWidth: number;
  @Prop({ default: 64, min: 30, max: 90 }) previewQuality: number;
  @Prop({ default: false }) useCustomStripe: boolean;
  @Prop({ trim: true }) stripePublishableKey?: string;
  @Prop({ select: false }) stripeSecretCipher?: string;
  @Prop({ select: false }) stripeWebhookSecretCipher?: string;
  @Prop({ trim: true }) stripeAccountLabel?: string;
  @Prop({ type: [Types.ObjectId], ref: 'Album', default: [] })
  saleAlbumIds: Types.ObjectId[];
  @Prop({ trim: true, maxlength: 160 }) coverTitle?: string;
  @Prop({ trim: true }) coverImageUrl?: string;
  @Prop({ trim: true }) termsText?: string;
}
export const StoreSettingsSchema = SchemaFactory.createForClass(StoreSettings);
