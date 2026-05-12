import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { HydratedDocument } from 'mongoose';

export enum BillingUnit {
  PER_MONTH = 'PER_MONTH',
  PER_YEAR = 'PER_YEAR',
}

export type SubscriptionPlanDocument = HydratedDocument<SubscriptionPlan>;

@Schema({ timestamps: true, autoIndex: true, virtuals: true })
export class SubscriptionPlan {
  @Prop({ required: true, trim: true })
  title: string;

  @Prop({ trim: true })
  description?: string;

  @Prop({ required: true, min: 0 })
  price: number;

  @Prop({ min: 0 })
  discount_price?: number;

  @Prop({ type: [Object], default: [] })
  permissions: Record<string, unknown>[];

  @Prop({ type: [String], default: [] })
  features: string[];

  @Prop({ default: 0 })
  order: number;

  @Prop({ default: false })
  isPopular: boolean;

  @Prop({ default: 0, min: 0 })
  credit: number;

  @Prop({ default: 'USD', uppercase: true, trim: true })
  currency: string;

  @Prop({ type: String, enum: BillingUnit, default: BillingUnit.PER_MONTH })
  billingUnit: BillingUnit;

  @Prop({ type: Number, default: null, min: 0 })
  monthlyCreateLimit?: number | null;

  @Prop({ default: true })
  isActive: boolean;
}

export const SubscriptionPlanSchema =
  SchemaFactory.createForClass(SubscriptionPlan);

SubscriptionPlanSchema.index({ billingUnit: 1, order: 1 });
SubscriptionPlanSchema.index({ isActive: 1 });