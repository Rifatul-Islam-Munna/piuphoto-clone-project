import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { HydratedDocument, Types } from 'mongoose';
export type ApiWebhookEndpointDocument=HydratedDocument<ApiWebhookEndpoint>;
@Schema({timestamps:true})
export class ApiWebhookEndpoint {
  @Prop({type:Types.ObjectId,ref:'User',required:true,index:true}) userId:Types.ObjectId;
  @Prop({type:Types.ObjectId,ref:'Event',required:true,index:true}) eventId:Types.ObjectId;
  @Prop({required:true,trim:true}) url:string;
  @Prop({required:true,select:false}) secret:string;
  @Prop({type:[String],default:['photo.created','photo.status','photo.ai','retouch.status','retouch.ready','retouch.published']}) eventTypes:string[];
  @Prop({default:true,index:true}) active:boolean;
}
export const ApiWebhookEndpointSchema=SchemaFactory.createForClass(ApiWebhookEndpoint);
