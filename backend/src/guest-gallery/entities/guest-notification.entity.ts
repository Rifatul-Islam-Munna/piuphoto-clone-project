import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { HydratedDocument, Types } from 'mongoose';

export type GuestNotificationDocument = HydratedDocument<GuestNotification>;

export enum GuestNotificationStatus {
  PENDING = 'pending',
  SENDING = 'sending',
  SENT = 'sent',
  FAILED = 'failed',
}

@Schema({ timestamps: true, autoIndex: true })
export class GuestNotification {
  @Prop({ type: Types.ObjectId, ref: 'Event', required: true, index: true })
  eventId: Types.ObjectId;
  @Prop({
    type: Types.ObjectId,
    ref: 'GuestFaceRegistration',
    required: true,
    index: true,
  })
  registrationId: Types.ObjectId;
  @Prop({ enum: ['email', 'whatsapp'], required: true, index: true }) channel:
    | 'email'
    | 'whatsapp';
  @Prop({ type: [Types.ObjectId], ref: 'EventImage', default: [] })
  photoIds: Types.ObjectId[];
  @Prop({
    enum: GuestNotificationStatus,
    default: GuestNotificationStatus.PENDING,
    index: true,
  })
  status: GuestNotificationStatus;
  @Prop({ required: true, index: true }) sendAfter: Date;
  @Prop({ default: 0 }) attempts: number;
  @Prop({ trim: true }) error?: string;
  @Prop() sentAt?: Date;
  @Prop() deliveredAt?: Date;
}

export const GuestNotificationSchema =
  SchemaFactory.createForClass(GuestNotification);
GuestNotificationSchema.index({
  eventId: 1,
  registrationId: 1,
  channel: 1,
  status: 1,
});
GuestNotificationSchema.index({ status: 1, sendAfter: 1 });
