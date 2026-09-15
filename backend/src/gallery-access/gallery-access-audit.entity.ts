import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { HydratedDocument, Types } from 'mongoose';

export type GalleryAccessAuditDocument = HydratedDocument<GalleryAccessAudit>;

@Schema({ timestamps: true, autoIndex: true })
export class GalleryAccessAudit {
  @Prop({ type: Types.ObjectId, ref: 'Event', required: true, index: true })
  eventId: Types.ObjectId;

  @Prop({ type: Types.ObjectId, ref: 'Album', index: true })
  albumId?: Types.ObjectId;

  @Prop({ trim: true, required: true }) action: string;
  @Prop({ trim: true }) actorId?: string;
  @Prop({ trim: true }) source?: string;
  @Prop({ type: Object }) metadata?: Record<string, unknown>;
}

export const GalleryAccessAuditSchema =
  SchemaFactory.createForClass(GalleryAccessAudit);
GalleryAccessAuditSchema.index({ eventId: 1, createdAt: -1 });
