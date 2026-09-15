import { ForbiddenException, HttpException, Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import axios from 'axios';
import { createHash, createHmac, randomBytes } from 'crypto';
import { Model, Types } from 'mongoose';
import { EventMemberService } from '../event-member/event-member.service';
import { Event, EventDocument } from '../event/entities/event.entity';
import { EventImage, EventImageDocument } from '../event-image/entities/event-image.entity';
import { CreateApiKeyDto, CreateApiWebhookDto } from './dto/external-api.dto';
import { ApiCredential, ApiCredentialDocument } from './entities/api-credential.entity';
import { ApiWebhookDelivery, ApiWebhookDeliveryDocument } from './entities/api-webhook-delivery.entity';
import { ApiWebhookEndpoint, ApiWebhookEndpointDocument } from './entities/api-webhook-endpoint.entity';
import { ApiUsageBucket, ApiUsageBucketDocument } from './entities/api-usage-bucket.entity';
import { ApiAuditLog, ApiAuditLogDocument } from './entities/api-audit-log.entity';

export type ApiActor={credentialId:string;userId:string;scopes:string[];eventIds:string[]};
@Injectable()
export class ExternalApiService implements OnModuleInit,OnModuleDestroy {
  private readonly logger=new Logger(ExternalApiService.name);
  private worker?:ReturnType<typeof setInterval>;
  private readonly quota=new Map<string,{hour:number,count:number}>();
  constructor(
    @InjectModel(ApiCredential.name) private readonly credentials:Model<ApiCredentialDocument>,
    @InjectModel(ApiWebhookEndpoint.name) private readonly endpoints:Model<ApiWebhookEndpointDocument>,
    @InjectModel(ApiWebhookDelivery.name) private readonly deliveries:Model<ApiWebhookDeliveryDocument>,
    @InjectModel(ApiUsageBucket.name) private readonly usage:Model<ApiUsageBucketDocument>,
    @InjectModel(ApiAuditLog.name) private readonly auditLogs:Model<ApiAuditLogDocument>,
    @InjectModel(Event.name) private readonly events:Model<EventDocument>,
    @InjectModel(EventImage.name) private readonly images:Model<EventImageDocument>,
    private readonly members:EventMemberService,
  ){}
  onModuleInit(){ this.worker=setInterval(()=>void this.flush(),10000); this.worker.unref?.(); void this.flush(); }
  onModuleDestroy(){ if(this.worker) clearInterval(this.worker); }
  private oid(id:string){ if(!Types.ObjectId.isValid(id)) throw new HttpException('Invalid id',400); return new Types.ObjectId(id); }
  private hash(value:string){ return createHash('sha256').update(value).digest('hex'); }

  async createKey(dto:CreateApiKeyDto,userId?:string,role?:string){
    if(!userId||!Types.ObjectId.isValid(userId)) throw new ForbiddenException('Login required');
    for(const eventId of dto.eventIds||[]) await this.members.assertCanManage(eventId,userId,role);
    const raw=`ppk_${randomBytes(30).toString('base64url')}`; const prefix=raw.slice(0,12);
    const data=await this.credentials.create({userId:this.oid(userId),name:dto.name,prefix,keyHash:this.hash(raw),scopes:[...new Set(dto.scopes)],eventIds:(dto.eventIds||[]).map(id=>this.oid(id)),active:true});
    return {message:'API key created. Copy it now; it will not be shown again.',apiKey:raw,data:{_id:String(data._id),name:data.name,prefix:data.prefix,scopes:data.scopes,eventIds:data.eventIds}};
  }
  async listKeys(userId?:string){ if(!userId||!Types.ObjectId.isValid(userId)) throw new ForbiddenException('Login required'); const data=await this.credentials.find({userId:this.oid(userId)}).select('name prefix scopes eventIds active hourlyQuota lastUsedAt createdAt').sort({createdAt:-1}).lean(); return {data,totalItems:data.length}; }
  async revokeKey(id:string,userId?:string){ if(!userId) throw new ForbiddenException('Login required'); const data=await this.credentials.findOneAndUpdate({_id:this.oid(id),userId:this.oid(userId)},{$set:{active:false}},{new:true}).select('name prefix active').lean(); if(!data) throw new HttpException('API key not found',404); return {message:'API key revoked',data}; }

  async authenticate(raw:string|undefined,scope:string,eventId?:string):Promise<ApiActor>{
    if(!raw) throw new ForbiddenException('x-api-key header required'); const credential=await this.credentials.findOne({keyHash:this.hash(raw),active:true}).select('+keyHash userId scopes eventIds hourlyQuota active').exec(); if(!credential) throw new ForbiddenException('Invalid API key');
    if(!credential.scopes.includes(scope)) throw new ForbiddenException(`API key requires ${scope}`);
    const hour=new Date().toISOString().slice(0,13); const key=String(credential._id);
    const bucket=await this.usage.findOneAndUpdate({credentialId:credential._id,hour},{$inc:{count:1},$setOnInsert:{credentialId:credential._id,hour,expiresAt:new Date(Date.now()+48*3600000)}},{upsert:true,new:true,setDefaultsOnInsert:false}).lean();
    if((bucket?.count||0)>credential.hourlyQuota) throw new HttpException('API key hourly quota exceeded',429);
    const eventIds=(credential.eventIds||[]).map(String); if(eventId){ if(eventIds.length&&!eventIds.includes(eventId)) throw new ForbiddenException('API key is not scoped to this event'); await this.members.assertCanAccess(eventId,String(credential.userId)); }
    credential.lastUsedAt=new Date(); await credential.save();
    await this.auditLogs.create({credentialId:credential._id,userId:credential.userId,eventId:eventId?this.oid(eventId):undefined,scope,action:scope,success:true});
    return {credentialId:key,userId:String(credential.userId),scopes:credential.scopes,eventIds};
  }

  async listAudit(userId?:string){ if(!userId||!Types.ObjectId.isValid(userId)) throw new ForbiddenException('Login required'); const credentialIds=await this.credentials.find({userId:this.oid(userId)}).distinct('_id'); const data=await this.auditLogs.find({credentialId:{$in:credentialIds}}).populate('credentialId','name prefix').sort({createdAt:-1}).limit(250).lean(); return {data,totalItems:data.length}; }
  async createWebhook(dto:CreateApiWebhookDto,userId?:string,role?:string){
    if(!userId) throw new ForbiddenException('Login required'); await this.members.assertCanManage(dto.eventId,userId,role); const secret=`whsec_${randomBytes(24).toString('base64url')}`;
    const row=await this.endpoints.create({userId:this.oid(userId),eventId:this.oid(dto.eventId),url:dto.url,secret,eventTypes:dto.eventTypes?.length?dto.eventTypes:undefined,active:true});
    return {message:'Webhook created. Copy the signing secret now.',signingSecret:secret,data:{_id:String(row._id),eventId:row.eventId,url:row.url,eventTypes:row.eventTypes,active:row.active}};
  }
  async listWebhooks(eventId:string,userId?:string,role?:string){ await this.members.assertCanManage(eventId,userId,role); const data=await this.endpoints.find({eventId:this.oid(eventId)}).select('url eventTypes active createdAt').sort({createdAt:-1}).lean(); return {data,totalItems:data.length}; }
  async removeWebhook(id:string,userId?:string,role?:string){ const row=await this.endpoints.findById(id).select('eventId userId').lean(); if(!row) throw new HttpException('Webhook not found',404); await this.members.assertCanManage(String(row.eventId),userId,role); await this.endpoints.deleteOne({_id:row._id}); return {message:'Webhook removed'}; }

  async queueWebhook(eventId:string,eventType:string,payload:Record<string,unknown>){
    if(!Types.ObjectId.isValid(eventId)) return; const rows=await this.endpoints.find({eventId:this.oid(eventId),active:true,eventTypes:eventType}).select('_id').lean(); if(!rows.length) return;
    await this.deliveries.insertMany(rows.map(row=>({endpointId:row._id,eventId:this.oid(eventId),eventType,payload,status:'pending',attempts:0,nextAttemptAt:new Date()})),{ordered:false}).catch(()=>undefined);
  }
  private async flush(){
    try{ const pending=await this.deliveries.find({status:'pending',nextAttemptAt:{$lte:new Date()}}).sort({nextAttemptAt:1}).limit(25).exec(); for(const item of pending) await this.deliver(item); }catch(error){ this.logger.warn(`api-webhook-worker ${String(error)}`); }
  }
  private async deliver(item:ApiWebhookDeliveryDocument){
    const claimed=await this.deliveries.findOneAndUpdate({_id:item._id,status:'pending'},{$set:{status:'sending'}},{new:true}); if(!claimed) return;
    try{ const endpoint=await this.endpoints.findOne({_id:claimed.endpointId,active:true}).select('+secret url').lean(); if(!endpoint) throw new Error('Webhook endpoint disabled'); const timestamp=Math.floor(Date.now()/1000).toString(); const body=JSON.stringify({id:String(claimed._id),type:claimed.eventType,eventId:String(claimed.eventId),createdAt:new Date().toISOString(),data:claimed.payload}); const signature=createHmac('sha256',endpoint.secret).update(`${timestamp}.${body}`).digest('hex'); await axios.post(endpoint.url,body,{headers:{'Content-Type':'application/json','x-piufoto-timestamp':timestamp,'x-piufoto-signature':signature,'x-piufoto-delivery-id':String(claimed._id)},timeout:15000}); await this.deliveries.updateOne({_id:claimed._id},{$set:{status:'sent',sentAt:new Date()},$unset:{error:''}}); }
    catch(error){ const attempts=claimed.attempts+1; const dead=attempts>=5; await this.deliveries.updateOne({_id:claimed._id},{$set:{status:dead?'dead':'pending',attempts,nextAttemptAt:new Date(Date.now()+Math.min(30,2**attempts)*60000),error:error instanceof Error?error.message:String(error)}}); }
  }

  async uploadStatus(eventId:string,imageId:string){
    if(!Types.ObjectId.isValid(imageId)) throw new HttpException('Invalid image id',400);
    const data=await this.images.findOne({_id:this.oid(imageId),eventId:this.oid(eventId)}).select('_id eventId albumId clientTransferId isEnhanced isPublished mediaType aiReviewStatus createdAt updatedAt').lean();
    if(!data) throw new HttpException('Upload status not found',404);
    const status=data.isPublished!==false?'published':data.aiReviewStatus==='rejected'?'review_rejected':'processing';
    return {eventImageId:String(data._id),eventId:String(data.eventId),albumId:data.albumId?String(data.albumId):undefined,clientTransferId:data.clientTransferId,status,isPublished:data.isPublished!==false,isEnhanced:Boolean(data.isEnhanced),mediaType:data.mediaType,aiReviewStatus:data.aiReviewStatus,createdAt:(data as any).createdAt,updatedAt:(data as any).updatedAt};
  }
  async listWebhookDeliveries(eventId:string,userId?:string,role?:string){
    await this.members.assertCanManage(eventId,userId,role);
    const data=await this.deliveries.find({eventId:this.oid(eventId)}).populate('endpointId','url active eventTypes').sort({createdAt:-1}).limit(100).lean();
    return {data,totalItems:data.length,dead:data.filter((item:any)=>item.status==='dead').length};
  }
  async retryWebhookDelivery(id:string,userId?:string,role?:string){
    const row=await this.deliveries.findById(this.oid(id)).select('eventId status').lean();
    if(!row) throw new HttpException('Webhook delivery not found',404);
    await this.members.assertCanManage(String(row.eventId),userId,role);
    const data=await this.deliveries.findByIdAndUpdate(row._id,{$set:{status:'pending',attempts:0,nextAttemptAt:new Date()},$unset:{error:'',sentAt:''}},{new:true}).lean();
    return {message:'Webhook delivery queued for retry',data};
  }
  async viewerEvent(eventId:string){ const event=await this.events.findById(eventId).select('title description image branding galleryVisibility gallerySlug').lean(); if(!event) throw new HttpException('Event not found',404); return {data:event}; }
  async viewerImages(eventId:string,albumId?:string){ const data=await this.images.find({eventId:this.oid(eventId),isPublished:{$ne:false},...(albumId?{albumId:this.oid(albumId)}:{})}).select('_id imageUrl albumId isEnhanced mediaType createdAt').sort({createdAt:-1}).limit(1000).lean(); return {data,totalItems:data.length}; }
}
