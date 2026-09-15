import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { HydratedDocument, Types } from 'mongoose';

export type GuestFaceRegistrationDocument =
  HydratedDocument<GuestFaceRegistration>;

@Schema({ timestamps: true, autoIndex: true })
export class GuestFaceRegistration {
  @Prop({ type: Types.ObjectId, ref: 'Event', required: true, index: true })
  eventId: Types.ObjectId;
  @Prop({ type: Types.ObjectId, ref: 'Album', index: true })
  albumId?: Types.ObjectId;
  @Prop({ required: true, unique: true, index: true, select: false })
  tokenHash: string;
  @Prop({ required: true, select: false }) tokenCipher: string;
  @Prop({ type: [[Number]], required: true, select: false })
  faceVectors: number[][];
  @Prop({ trim: true, lowercase: true }) email?: string;
  @Prop({ trim: true }) whatsapp?: string;
  @Prop({ trim: true, index: true, select: false }) emailLookupHash?: string;
  @Prop({ trim: true, index: true, select: false }) mobileLookupHash?: string;
  @Prop({ default: false, index: true }) globalProfile: boolean;
  @Prop({ default: 1, min: 1 }) profileRevision: number;
  @Prop({ default: false }) notifyEmail: boolean;
  @Prop({ default: false }) notifyWhatsapp: boolean;
  @Prop({ required: true }) consentAt: Date;
  @Prop({ trim: true, default: 'gallery' }) consentSource: string;
  @Prop({ index: true }) expiresAt?: Date;
  @Prop() lastSeenAt?: Date;
  @Prop() lastMatchedAt?: Date;
  @Prop() lastNotificationAt?: Date;
  @Prop({ trim: true }) selfieFingerprint?: string;
  @Prop({ type: [String], default: [], select: false })
  selfieFingerprints: string[];
}

export const GuestFaceRegistrationSchema = SchemaFactory.createForClass(
  GuestFaceRegistration,
);
GuestFaceRegistrationSchema.index({ expiresAt: 1 }, { expireAfterSeconds: 0 });
GuestFaceRegistrationSchema.index({ eventId: 1, createdAt: -1 });
GuestFaceRegistrationSchema.index({
  eventId: 1,
  mobileLookupHash: 1,
  expiresAt: 1,
});
GuestFaceRegistrationSchema.index({
  globalProfile: 1,
  emailLookupHash: 1,
  mobileLookupHash: 1,
});
GuestFaceRegistrationSchema.index({ globalProfile: 1, lastSeenAt: -1 });
