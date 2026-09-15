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

  @Prop({ type: Types.ObjectId, ref: 'Album', index: true })
  albumId?: Types.ObjectId;

  @Prop({ default: false, index: true })
  isEnhanced: boolean;

  @Prop({ type: Types.ObjectId, ref: 'EventImage', index: true })
  enhancedFromId?: Types.ObjectId;

  @Prop({ default: true, index: true })
  isPublished: boolean;

  @Prop({ trim: true })
  clientTransferId?: string;

  @Prop({ unique: true, sparse: true, trim: true })
  falRequestId?: string;

  @Prop({ type: String, enum: ['photo', 'video'], default: 'photo', index: true })
  mediaType: 'photo' | 'video';

  @Prop({ default: false, index: true })
  aiRecommended: boolean;

  @Prop({
    type: String,
    enum: ['pending', 'approved', 'flagged', 'rejected'],
    default: 'pending',
    index: true,
  })
  aiReviewStatus: 'pending' | 'approved' | 'flagged' | 'rejected';

  @Prop({ min: 0, max: 100 })
  aiQualityScore?: number;

  @Prop({ min: 0 })
  aiBlurScore?: number;

  @Prop({ type: [String], default: [] })
  aiReviewReasons: string[];

  @Prop({ trim: true })
  aiDescription?: string;

  @Prop({ type: [String], default: [] })
  aiTags: string[];

  @Prop({ type: [String], default: [] })
  recognizedNumbers: string[];

  @Prop({ type: [String], default: [] })
  outfitTags: string[];

  @Prop({ trim: true, index: true })
  perceptualHash?: string;

  @Prop({ type: Types.ObjectId, ref: 'EventImage' })
  duplicateOfId?: Types.ObjectId;

  @Prop({
    type: String,
    enum: ['approve', 'reject', 'clear'],
  })
  reviewerDecision?: 'approve' | 'reject' | 'clear';

  @Prop({ type: Types.ObjectId, ref: 'User' })
  reviewedBy?: Types.ObjectId;

  @Prop()
  reviewedAt?: Date;
}

export const EventImageSchema = SchemaFactory.createForClass(EventImage);

EventImageSchema.index({ eventId: 1, createdAt: -1 });
EventImageSchema.index({ eventId: 1, userTakenBy: 1, createdAt: -1 });
EventImageSchema.index({ eventId: 1, albumId: 1, createdAt: -1 });

EventImageSchema.index(
  { eventId: 1, clientTransferId: 1 },
  {
    unique: true,
    name: 'event_client_transfer_unique',
    partialFilterExpression: { clientTransferId: { $type: 'string' } },
  },
);
