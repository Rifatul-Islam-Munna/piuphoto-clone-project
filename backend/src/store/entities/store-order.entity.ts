import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { HydratedDocument, Types } from 'mongoose';
export enum StoreOrderStatus { PENDING='pending', PAID='paid', FAILED='failed', REFUNDED='refunded' }
export type StoreOrderDocument = HydratedDocument<StoreOrder>;
@Schema({ timestamps: true, autoIndex: true })
export class StoreOrder {
  @Prop({ required: true, unique: true, index: true, trim: true }) orderNo: string;
  @Prop({ type: Types.ObjectId, ref: 'Event', required: true, index: true }) eventId: Types.ObjectId;
  @Prop({ type: [Types.ObjectId], ref: 'EventImage', required: true }) imageIds: Types.ObjectId[];
  @Prop({ required: true, lowercase: true, trim: true, index: true }) email: string;
  @Prop({ trim: true }) whatsapp?: string;
  @Prop({ required: true, min: 0 }) amount: number;
  @Prop({ required: true, uppercase: true, trim: true }) currency: string;
  @Prop({ enum: StoreOrderStatus, default: StoreOrderStatus.PENDING, index: true }) status: StoreOrderStatus;
  @Prop({ unique: true, sparse: true, trim: true, index: true }) checkoutIdempotencyKey?: string;
  @Prop({ unique: true, sparse: true, trim: true }) stripeSessionId?: string;
  @Prop({ trim: true }) stripeCheckoutUrl?: string;
  @Prop({ trim: true, index: true }) paymentIntentId?: string;
  @Prop({ trim: true, index: true }) downloadTokenHash?: string;
  @Prop({ select: false }) downloadTokenCipher?: string;
  @Prop() downloadExpiresAt?: Date;
  @Prop() paidAt?: Date;
  @Prop() refundedAt?: Date;
  @Prop({ index: true }) lastPaymentCheckAt?: Date;
  @Prop() deliverySentAt?: Date;
  @Prop() deliverySendingAt?: Date;
  @Prop({ trim: true }) deliveryError?: string;
  @Prop({ default: 0 }) deliveryAttempts: number;
}
export const StoreOrderSchema = SchemaFactory.createForClass(StoreOrder);
StoreOrderSchema.index({ eventId: 1, createdAt: -1 });
StoreOrderSchema.index({ email: 1, createdAt: -1 });
