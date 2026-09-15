import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { HydratedDocument, Types } from 'mongoose';

export type RetouchDocument = HydratedDocument<RetouchJob>;

@Schema({ timestamps: true, autoIndex: true })
export class RetouchJob {
  @Prop({ type: Types.ObjectId, ref: 'Event', required: true, index: true })
  eventId: Types.ObjectId;

  @Prop({ type: [Types.ObjectId], ref: 'EventImage', default: [] })
  imageIds: Types.ObjectId[];

  @Prop({ type: Types.ObjectId, ref: 'User' })
  retoucherId?: Types.ObjectId;

  @Prop({ type: Types.ObjectId, ref: 'User' })
  reviewerId?: Types.ObjectId;

  @Prop({ enum: ['incoming','downloaded','retouching','ready_review','approved','published'], default: 'incoming', index: true })
  status: string;

  @Prop({ default: '' })
  note: string;

  @Prop({ default: false })
  bypassReview: boolean;
}

export const RetouchJobSchema = SchemaFactory.createForClass(RetouchJob);
RetouchJobSchema.index({ eventId: 1, status: 1 });
