import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { HydratedDocument, Types } from 'mongoose';

export enum RetouchJobStatus {
  INCOMING = 'incoming',
  ASSIGNED = 'assigned',
  DOWNLOADED = 'downloaded',
  RETOUCHING = 'retouching',
  READY_FOR_REVIEW = 'ready_for_review',
  APPROVED = 'approved',
  REJECTED = 'rejected',
  PUBLISHED = 'published',
  FAILED = 'failed',
}

export type RetouchJobDocument = HydratedDocument<RetouchJob>;

@Schema({ timestamps: true, autoIndex: true })
export class RetouchJob {
  @Prop({ type: Types.ObjectId, ref: 'Event', required: true, index: true }) eventId: Types.ObjectId;
  @Prop({ type: Types.ObjectId, ref: 'EventImage', required: true, unique: true, index: true }) eventImageId: Types.ObjectId;
  @Prop({ type: Types.ObjectId, ref: 'Album', index: true }) albumId?: Types.ObjectId;
  @Prop({ type: Types.ObjectId, ref: 'User', index: true }) photographerId?: Types.ObjectId;
  @Prop({ type: Types.ObjectId, ref: 'User', index: true }) assignedRetoucherId?: Types.ObjectId;
  @Prop({ type: Types.ObjectId, ref: 'User' }) reviewedBy?: Types.ObjectId;
  @Prop({ type: Types.ObjectId, ref: 'EventImage' }) outputEventImageId?: Types.ObjectId;
  @Prop({ enum: RetouchJobStatus, default: RetouchJobStatus.INCOMING, index: true }) status: RetouchJobStatus;
  @Prop({ required: true, trim: true }) originalImageUrl: string;
  @Prop({ required: true, trim: true }) currentImageUrl: string;
  @Prop({ trim: true }) retouchedImageUrl?: string;
  @Prop({ trim: true }) checksum?: string;
  @Prop({ trim: true }) internalNote?: string;
  @Prop({ trim: true }) rejectionReason?: string;
  @Prop({ trim: true }) desktopDeviceId?: string;
  @Prop() assignedAt?: Date;
  @Prop() downloadedAt?: Date;
  @Prop() retouchStartedAt?: Date;
  @Prop() readyForReviewAt?: Date;
  @Prop() reviewedAt?: Date;
  @Prop() publishedAt?: Date;
  @Prop() desktopLastSeenAt?: Date;
}
export const RetouchJobSchema = SchemaFactory.createForClass(RetouchJob);
RetouchJobSchema.index({ eventId: 1, status: 1, createdAt: -1 });
RetouchJobSchema.index({ eventId: 1, assignedRetoucherId: 1, status: 1 });
