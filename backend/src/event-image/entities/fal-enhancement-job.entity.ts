import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { HydratedDocument, Types } from 'mongoose';

export type FalEnhancementJobDocument = HydratedDocument<FalEnhancementJob>;

export enum FalEnhancementJobStatus {
  PENDING = 'pending',
  COMPLETED = 'completed',
  FAILED = 'failed',
}

@Schema({ timestamps: true })
export class FalEnhancementJob {
  @Prop({ required: true, unique: true, index: true, trim: true })
  requestId: string;

  @Prop({ required: true, enum: ['puiphoto'], default: 'puiphoto' })
  type: 'puiphoto';

  @Prop({ type: Types.ObjectId, ref: 'Event', required: true, index: true })
  eventId: Types.ObjectId;

  @Prop({ type: Types.ObjectId, ref: 'User', required: true })
  uploaderId: Types.ObjectId;

  @Prop({ type: Types.ObjectId, ref: 'User', required: true })
  ownerId: Types.ObjectId;

  @Prop({ type: Types.ObjectId, ref: 'Album' })
  albumId?: Types.ObjectId;

  @Prop({ required: true, trim: true })
  sourceImageUrl: string;

  @Prop({ required: true, default: 3 })
  creditsCharged: number;

  @Prop({
    required: true,
    enum: FalEnhancementJobStatus,
    default: FalEnhancementJobStatus.PENDING,
    index: true,
  })
  status: FalEnhancementJobStatus;

  @Prop({ trim: true })
  error?: string;
}

export const FalEnhancementJobSchema =
  SchemaFactory.createForClass(FalEnhancementJob);

