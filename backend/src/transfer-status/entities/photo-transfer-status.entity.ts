import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { HydratedDocument, Types } from 'mongoose';

export enum PhotoTransferState {
  DETECTED = 'detected',
  STORED = 'stored',
  QUEUED = 'queued',
  UPLOADING = 'uploading',
  PROCESSING = 'processing',
  PUBLISHED = 'published',
  DELIVERED = 'delivered',
  FAILED = 'failed',
}

export type PhotoTransferStatusDocument = HydratedDocument<PhotoTransferStatus>;

@Schema({ timestamps: true, autoIndex: true, virtuals: true })
export class PhotoTransferStatus {
  @Prop({ type: Types.ObjectId, ref: 'Event', required: true, index: true })
  eventId: Types.ObjectId;

  @Prop({ type: Types.ObjectId, ref: 'User', required: true, index: true })
  photographerId: Types.ObjectId;

  @Prop({ required: true, trim: true })
  clientTransferId: string;

  @Prop({ required: true, trim: true })
  filename: string;

  @Prop({ trim: true, default: 'camera' })
  source: string;

  @Prop({ trim: true })
  cameraId?: string;

  @Prop({ trim: true, enum: ['photo', 'video'], default: 'photo' })
  mediaType: 'photo' | 'video';

  @Prop({ type: Types.ObjectId, ref: 'Album', index: true })
  albumId?: Types.ObjectId;

  @Prop({ type: Types.ObjectId, ref: 'UploadSession', index: true })
  uploadSessionId?: Types.ObjectId;

  @Prop({
    type: String,
    enum: PhotoTransferState,
    default: PhotoTransferState.DETECTED,
    index: true,
  })
  status: PhotoTransferState;

  @Prop({ min: 0, max: 100, default: 0 })
  progress: number;

  @Prop({ min: 0, default: 0 })
  bytesSent: number;

  @Prop({ min: 0, default: 0 })
  bytesTotal: number;

  @Prop({ min: 0, default: 0 })
  bytesPerSecond: number;

  @Prop({ trim: true })
  error?: string;

  @Prop({ trim: true })
  imageUrl?: string;

  @Prop({ type: Types.ObjectId, ref: 'EventImage', index: true })
  eventImageId?: Types.ObjectId;

  @Prop()
  capturedAt?: Date;

  @Prop()
  uploadedAt?: Date;

  @Prop()
  deliveredAt?: Date;
}

export const PhotoTransferStatusSchema =
  SchemaFactory.createForClass(PhotoTransferStatus);

PhotoTransferStatusSchema.index(
  { eventId: 1, clientTransferId: 1 },
  { unique: true, name: 'event_client_transfer_unique' },
);
PhotoTransferStatusSchema.index({ eventId: 1, createdAt: -1 });
PhotoTransferStatusSchema.index({ eventId: 1, status: 1, updatedAt: -1 });
PhotoTransferStatusSchema.index({
  eventId: 1,
  photographerId: 1,
  createdAt: -1,
});
