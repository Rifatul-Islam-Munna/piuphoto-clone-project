import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { HydratedDocument, Types } from 'mongoose';
import { BillingUnit } from './subscription-plan.entity';

export enum SubscriptionPlanPurchaseStatus {
  PENDING = 'pending',
  COMPLETED = 'completed',
}

export type SubscriptionPlanPurchaseDocument =
  HydratedDocument<SubscriptionPlanPurchase>;

@Schema({ timestamps: true, autoIndex: true, virtuals: true })
export class SubscriptionPlanPurchase {
  @Prop({ type: Types.ObjectId, ref: 'SubscriptionPlan', required: true, index: true })
  planId: Types.ObjectId;

  @Prop({ type: Types.ObjectId, ref: 'User', required: true, index: true })
  userId: Types.ObjectId;

  @Prop({ required: true, trim: true, unique: true })
  stripeSessionId: string;

  @Prop({ trim: true })
  stripePaymentIntentId?: string;

  @Prop({
    type: String,
    enum: SubscriptionPlanPurchaseStatus,
    default: SubscriptionPlanPurchaseStatus.PENDING,
    index: true,
  })
  status: SubscriptionPlanPurchaseStatus;

  @Prop({ required: true, min: 0 })
  price: number;

  @Prop({ required: true, uppercase: true, trim: true })
  currency: string;

  @Prop({ required: true, min: 0 })
  credit: number;

  @Prop({ type: String, enum: BillingUnit, required: true })
  billingUnit: BillingUnit;

  @Prop()
  completedAt?: Date;

  createdAt?: Date;

  updatedAt?: Date;
}

export const SubscriptionPlanPurchaseSchema = SchemaFactory.createForClass(
  SubscriptionPlanPurchase,
);

SubscriptionPlanPurchaseSchema.index({ userId: 1, createdAt: -1 });
