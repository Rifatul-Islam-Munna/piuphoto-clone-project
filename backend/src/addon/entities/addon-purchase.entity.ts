import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { HydratedDocument, Types } from 'mongoose';

export enum AddonPurchaseStatus {
  PENDING = 'pending',
  COMPLETED = 'completed',
}

export type AddonPurchaseDocument = HydratedDocument<AddonPurchase>;

@Schema({ timestamps: true, autoIndex: true, virtuals: true })
export class AddonPurchase {
  @Prop({ type: Types.ObjectId, ref: 'Addon', required: true, index: true })
  addonId: Types.ObjectId;

  @Prop({ type: Types.ObjectId, ref: 'User', required: true, index: true })
  userId: Types.ObjectId;

  @Prop({ required: true, trim: true, unique: true })
  stripeSessionId: string;

  @Prop({ trim: true })
  stripePaymentIntentId?: string;

  @Prop({
    type: String,
    enum: AddonPurchaseStatus,
    default: AddonPurchaseStatus.PENDING,
    index: true,
  })
  status: AddonPurchaseStatus;

  @Prop({ required: true, min: 1 })
  credit: number;

  @Prop({ required: true, min: 0 })
  price: number;

  @Prop({ required: true, uppercase: true, trim: true })
  currency: string;

  @Prop()
  completedAt?: Date;

  createdAt?: Date;

  updatedAt?: Date;
}

export const AddonPurchaseSchema =
  SchemaFactory.createForClass(AddonPurchase);

AddonPurchaseSchema.index({ userId: 1, createdAt: -1 });
