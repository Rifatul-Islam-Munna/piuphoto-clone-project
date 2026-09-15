import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { HydratedDocument, Types } from 'mongoose';

export enum UploadSessionStatus {
  ACTIVE = 'active',
  ENDED = 'ended',
}

export type UploadSessionDocument = HydratedDocument<UploadSession>;

@Schema({ timestamps: true, autoIndex: true, virtuals: true })
export class UploadSession {
  @Prop({ type: Types.ObjectId, ref: 'Event', required: true, index: true })
  eventId: Types.ObjectId;

  @Prop({ type: Types.ObjectId, ref: 'User', required: true, index: true })
  photographerId: Types.ObjectId;

  @Prop({ type: Types.ObjectId, ref: 'Album', index: true })
  albumId?: Types.ObjectId;

  @Prop({ required: true, trim: true, default: 'camera' })
  source: string;

  @Prop({ trim: true })
  cameraId?: string;

  @Prop({
    type: String,
    enum: UploadSessionStatus,
    default: UploadSessionStatus.ACTIVE,
    index: true,
  })
  status: UploadSessionStatus;

  @Prop({ required: true, default: Date.now })
  startedAt: Date;

  @Prop({ required: true, default: Date.now, index: true })
  lastSeenAt: Date;

  @Prop()
  endedAt?: Date;

  @Prop({ min: 0, default: 0 })
  transferCount: number;
}

export const UploadSessionSchema = SchemaFactory.createForClass(UploadSession);

UploadSessionSchema.index({ eventId: 1, lastSeenAt: -1 });
UploadSessionSchema.index({ eventId: 1, photographerId: 1, status: 1 });
UploadSessionSchema.index({
  eventId: 1,
  photographerId: 1,
  source: 1,
  cameraId: 1,
  lastSeenAt: -1,
});
