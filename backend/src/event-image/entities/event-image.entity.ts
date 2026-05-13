import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { HydratedDocument, Types } from 'mongoose';

export type EventImageDocument = HydratedDocument<EventImage>;

@Schema({ timestamps: true, autoIndex: true, virtuals: true })
export class EventImage {
  @Prop({ type: Types.ObjectId, ref: 'Event', required: true, index: true })
  eventId: Types.ObjectId;

  @Prop({ required: true, trim: true })
  imageUrl: string;

  @Prop({ type: Types.ObjectId, ref: 'User', required: true, index: true })
  userTakenBy: Types.ObjectId;

  @Prop({ trim: true, index: true })
  referenceId?: string;

  @Prop({ default: false, index: true })
  isEnhanced: boolean;
}

export const EventImageSchema = SchemaFactory.createForClass(EventImage);

EventImageSchema.index({ eventId: 1, createdAt: -1 });
EventImageSchema.index({ eventId: 1, userTakenBy: 1, createdAt: -1 });
