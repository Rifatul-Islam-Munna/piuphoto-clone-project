import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { HydratedDocument, Types } from 'mongoose';
export type ApiWebhookDeliveryDocument=HydratedDocument<ApiWebhookDelivery>;
@Schema({timestamps:true,autoIndex:true})
export class ApiWebhookDelivery {
  @Prop({type:Types.ObjectId,ref:'ApiWebhookEndpoint',required:true,index:true}) endpointId:Types.ObjectId;
  @Prop({type:Types.ObjectId,ref:'Event',required:true,index:true}) eventId:Types.ObjectId;
  @Prop({required:true,trim:true}) eventType:string;
  @Prop({type:Object,required:true}) payload:Record<string,unknown>;
  @Prop({enum:['pending','sending','sent','dead'],default:'pending',index:true}) status:'pending'|'sending'|'sent'|'dead';
  @Prop({default:0}) attempts:number;
  @Prop({required:true,index:true,default:()=>new Date()}) nextAttemptAt:Date;
  @Prop({trim:true}) error?:string;
  @Prop() sentAt?:Date;
}
export const ApiWebhookDeliverySchema=SchemaFactory.createForClass(ApiWebhookDelivery);
ApiWebhookDeliverySchema.index({status:1,nextAttemptAt:1});
