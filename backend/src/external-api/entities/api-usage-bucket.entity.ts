import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { HydratedDocument, Types } from 'mongoose';
export type ApiUsageBucketDocument=HydratedDocument<ApiUsageBucket>;
@Schema({timestamps:true})
export class ApiUsageBucket {
  @Prop({type:Types.ObjectId,ref:'ApiCredential',required:true,index:true}) credentialId:Types.ObjectId;
  @Prop({required:true,index:true,trim:true}) hour:string;
  @Prop({default:0,min:0}) count:number;
  @Prop({required:true,index:true}) expiresAt:Date;
}
export const ApiUsageBucketSchema=SchemaFactory.createForClass(ApiUsageBucket);
ApiUsageBucketSchema.index({credentialId:1,hour:1},{unique:true});
ApiUsageBucketSchema.index({expiresAt:1},{expireAfterSeconds:0});
