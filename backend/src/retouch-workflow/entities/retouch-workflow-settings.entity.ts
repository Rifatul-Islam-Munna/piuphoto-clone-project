import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { HydratedDocument, Types } from 'mongoose';
export type RetouchWorkflowSettingsDocument = HydratedDocument<RetouchWorkflowSettings>;
@Schema({ timestamps: true })
export class RetouchWorkflowSettings {
  @Prop({ type: Types.ObjectId, ref: 'Event', required: true, unique: true, index: true }) eventId: Types.ObjectId;
  @Prop({ default: false }) bypassReviewer: boolean;
  @Prop({ default: true }) autoPublishApproved: boolean;
  @Prop({ default: 3, min: 1, max: 12 }) desktopDownloadConcurrency: number;
}
export const RetouchWorkflowSettingsSchema = SchemaFactory.createForClass(RetouchWorkflowSettings);
