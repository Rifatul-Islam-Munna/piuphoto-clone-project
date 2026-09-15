import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { HydratedDocument, Types } from 'mongoose';
export type ApiCredentialDocument=HydratedDocument<ApiCredential>;
@Schema({timestamps:true,autoIndex:true})
export class ApiCredential {
  @Prop({type:Types.ObjectId,ref:'User',required:true,index:true}) userId:Types.ObjectId;
  @Prop({required:true,trim:true}) name:string;
  @Prop({required:true,trim:true,index:true}) prefix:string;
  @Prop({required:true,unique:true,index:true,select:false}) keyHash:string;
  @Prop({type:[String],default:[]}) scopes:string[];
  @Prop({type:[Types.ObjectId],ref:'Event',default:[]}) eventIds:Types.ObjectId[];
  @Prop({default:true,index:true}) active:boolean;
  @Prop({default:1000,min:60,max:100000}) hourlyQuota:number;
  @Prop() lastUsedAt?:Date;
}
export const ApiCredentialSchema=SchemaFactory.createForClass(ApiCredential);
ApiCredentialSchema.index({userId:1,createdAt:-1});
