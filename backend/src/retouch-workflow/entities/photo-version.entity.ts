import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { HydratedDocument, Types } from 'mongoose';

export type PhotoVersionDocument = HydratedDocument<PhotoVersion>;
@Schema({ timestamps: true, autoIndex: true })
export class PhotoVersion {
  @Prop({ type: Types.ObjectId, ref: 'Event', required: true, index: true }) eventId: Types.ObjectId;
  @Prop({ type: Types.ObjectId, ref: 'EventImage', required: true, index: true }) eventImageId: Types.ObjectId;
  @Prop({ type: Types.ObjectId, ref: 'RetouchJob', index: true }) retouchJobId?: Types.ObjectId;
  @Prop({ type: Types.ObjectId, ref: 'User' }) createdBy?: Types.ObjectId;
  @Prop({ required: true, min: 1 }) version: number;
  @Prop({ enum: ['original', 'ai', 'retouched'], required: true }) type: 'original' | 'ai' | 'retouched';
  @Prop({ required: true, trim: true }) imageUrl: string;
  @Prop({ trim: true }) checksum?: string;
  @Prop({ trim: true }) note?: string;
}
export const PhotoVersionSchema = SchemaFactory.createForClass(PhotoVersion);
PhotoVersionSchema.index({ eventImageId: 1, version: 1 }, { unique: true });
