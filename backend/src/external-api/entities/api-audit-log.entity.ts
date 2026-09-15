import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { HydratedDocument, Types } from 'mongoose';
export type ApiAuditLogDocument=HydratedDocument<ApiAuditLog>;
@Schema({timestamps:true})
export class ApiAuditLog {
  @Prop({type:Types.ObjectId,ref:'ApiCredential',required:true,index:true}) credentialId:Types.ObjectId;
  @Prop({type:Types.ObjectId,ref:'User',required:true,index:true}) userId:Types.ObjectId;
  @Prop({type:Types.ObjectId,ref:'Event',index:true}) eventId?:Types.ObjectId;
  @Prop({required:true,index:true,trim:true}) scope:string;
  @Prop({trim:true}) action?:string;
  @Prop({trim:true}) requestId?:string;
  @Prop({default:true}) success:boolean;
}
export const ApiAuditLogSchema=SchemaFactory.createForClass(ApiAuditLog);
ApiAuditLogSchema.index({credentialId:1,createdAt:-1});
ApiAuditLogSchema.index({eventId:1,createdAt:-1});
