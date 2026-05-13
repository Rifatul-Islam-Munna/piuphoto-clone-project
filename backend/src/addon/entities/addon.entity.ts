import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { HydratedDocument } from 'mongoose';

export type AddonDocument = HydratedDocument<Addon>;

@Schema({ timestamps: true, autoIndex: true, virtuals: true })
export class Addon {
  @Prop({ required: true, trim: true })
  title: string;

  @Prop({ trim: true })
  description?: string;

  @Prop({ required: true, min: 1 })
  credit: number;

  @Prop({ required: true, min: 0 })
  price: number;

  @Prop({ default: 'USD', uppercase: true, trim: true })
  currency: string;

  @Prop({ default: 0 })
  order: number;

  @Prop({ default: true })
  isActive: boolean;
}

export const AddonSchema = SchemaFactory.createForClass(Addon);

AddonSchema.index({ isActive: 1, order: 1 });

