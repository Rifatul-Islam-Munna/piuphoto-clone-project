import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { HydratedDocument, Types } from 'mongoose';
export type AnalyticsEventDocument = HydratedDocument<AnalyticsEvent>;
@Schema({timestamps:true,autoIndex:true})
export class AnalyticsEvent {
  @Prop({type:Types.ObjectId,ref:'Event',required:true,index:true}) eventId:Types.ObjectId;
  @Prop({type:Types.ObjectId,ref:'EventImage',index:true}) imageId?:Types.ObjectId;
  @Prop({type:Types.ObjectId,ref:'Album',index:true}) albumId?:Types.ObjectId;
  @Prop({required:true,index:true,trim:true}) type:string;
  @Prop({trim:true,index:true}) viewerHash?:string;
  @Prop({trim:true}) channel?:string;
  @Prop({type:Object,default:{}}) metadata?:Record<string,unknown>;
}
export const AnalyticsEventSchema=SchemaFactory.createForClass(AnalyticsEvent);
AnalyticsEventSchema.index({eventId:1,type:1,createdAt:-1});
AnalyticsEventSchema.index({eventId:1,viewerHash:1,createdAt:-1});
