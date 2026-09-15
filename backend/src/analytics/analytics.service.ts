import { HttpException, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { InjectModel } from '@nestjs/mongoose';
import { createHash } from 'crypto';
import { Model, Types } from 'mongoose';
import { EventMemberService } from '../event-member/event-member.service';
import { Event, EventDocument } from '../event/entities/event.entity';
import { EventImage, EventImageDocument } from '../event-image/entities/event-image.entity';
import { FalEnhancementJob, FalEnhancementJobDocument } from '../event-image/entities/fal-enhancement-job.entity';
import { GuestFaceRegistration, GuestFaceRegistrationDocument } from '../guest-gallery/entities/guest-face-registration.entity';
import { GuestNotification, GuestNotificationDocument } from '../guest-gallery/entities/guest-notification.entity';
import { RetouchJob, RetouchJobDocument } from '../retouch-workflow/entities/retouch-job.entity';
import { StoreOrder, StoreOrderDocument, StoreOrderStatus } from '../store/entities/store-order.entity';
import { PhotoTransferStatus, PhotoTransferStatusDocument } from '../transfer-status/entities/photo-transfer-status.entity';
import { AnalyticsSummaryDto, TrackAnalyticsDto } from './dto/analytics.dto';
import { AnalyticsEvent, AnalyticsEventDocument } from './entities/analytics-event.entity';

@Injectable()
export class AnalyticsService {
  constructor(
    @InjectModel(AnalyticsEvent.name) private readonly eventsLog:Model<AnalyticsEventDocument>,
    @InjectModel(Event.name) private readonly events:Model<EventDocument>,
    @InjectModel(EventImage.name) private readonly images:Model<EventImageDocument>,
    @InjectModel(FalEnhancementJob.name) private readonly aiJobs:Model<FalEnhancementJobDocument>,
    @InjectModel(GuestFaceRegistration.name) private readonly guests:Model<GuestFaceRegistrationDocument>,
    @InjectModel(GuestNotification.name) private readonly notifications:Model<GuestNotificationDocument>,
    @InjectModel(RetouchJob.name) private readonly retouch:Model<RetouchJobDocument>,
    @InjectModel(StoreOrder.name) private readonly orders:Model<StoreOrderDocument>,
    @InjectModel(PhotoTransferStatus.name) private readonly transfers:Model<PhotoTransferStatusDocument>,
    private readonly members:EventMemberService,
    private readonly config:ConfigService,
  ){}
  private oid(id:string){ if(!Types.ObjectId.isValid(id)) throw new HttpException('Invalid event id',400); return new Types.ObjectId(id); }
  fingerprint(raw:string){ return createHash('sha256').update(`${this.config.get<string>('ANALYTICS_SALT')||this.config.get<string>('ACCESS_TOKEN')||'analytics'}:${raw}`).digest('hex'); }
  async track(dto:TrackAnalyticsDto,viewerHash:string){
    const event=await this.events.findOne({_id:this.oid(dto.eventId),isActive:true,isPublished:true}).select('_id').lean(); if(!event) throw new HttpException('Event unavailable',404);
    if(dto.imageId){ const exists=await this.images.exists({_id:this.oid(dto.imageId),eventId:event._id,isPublished:{$ne:false}}); if(!exists) throw new HttpException('Photo unavailable',404); }
    await this.eventsLog.create({eventId:event._id,imageId:dto.imageId?this.oid(dto.imageId):undefined,albumId:dto.albumId?this.oid(dto.albumId):undefined,type:dto.type,viewerHash,channel:dto.channel});
    return {ok:true};
  }
  private range(query:AnalyticsSummaryDto){ const createdAt:any={}; if(query.from){ const d=new Date(query.from); if(!Number.isNaN(d.getTime())) createdAt.$gte=d; } if(query.to){ const d=new Date(query.to); if(!Number.isNaN(d.getTime())) createdAt.$lte=d; } return Object.keys(createdAt).length?createdAt:undefined; }
  async summary(query:AnalyticsSummaryDto,userId?:string,role?:string){
    await this.members.assertCanManage(query.eventId,userId,role); const eventId=this.oid(query.eventId); const createdAt=this.range(query); const logMatch:any={eventId,...(createdAt?{createdAt}:{}),...(query.albumId?{albumId:this.oid(query.albumId)}:{}),...(query.channel?{channel:query.channel}:{})};
    const imageFilter:any={eventId,...(createdAt?{createdAt}:{}),...(query.albumId?{albumId:this.oid(query.albumId)}:{}),...(query.photographerId?{userTakenBy:this.oid(query.photographerId)}:{})};
    const [eventCounts,uniqueViewers,daily,photoCounts,publishedCount,photographers,retouchCounts,retouchTurnaround,paid,orderCounts,aiCounts,guestCount,notificationCounts,transferCounts]=await Promise.all([
      this.eventsLog.aggregate<{_id:string;count:number}>([{$match:logMatch},{$group:{_id:'$type',count:{$sum:1}}}]),
      this.eventsLog.distinct('viewerHash',{...logMatch,type:'gallery_visit',viewerHash:{$exists:true,$ne:''}}),
      this.eventsLog.aggregate<{_id:string;count:number}>([{$match:logMatch},{$group:{_id:{$dateToString:{format:'%Y-%m-%d',date:'$createdAt'}},count:{$sum:1}}},{$sort:{_id:1}}]),
      this.images.countDocuments({...imageFilter,isEnhanced:{$ne:true}}),
      this.images.countDocuments({...imageFilter,isPublished:{$ne:false}}),
      this.images.aggregate<{_id:Types.ObjectId;count:number}>([{$match:imageFilter},{$group:{_id:'$userTakenBy',count:{$sum:1}}},{$sort:{count:-1}},{$limit:20},{$lookup:{from:'users',localField:'_id',foreignField:'_id',as:'user'}},{$unwind:{path:'$user',preserveNullAndEmptyArrays:true}},{$project:{_id:1,count:1,name:'$user.name'}}]),
      this.retouch.aggregate<{_id:string;count:number}>([{$match:{eventId}},{$group:{_id:'$status',count:{$sum:1}}}]),
      this.retouch.aggregate<{avgMs:number}>([{$match:{eventId,retouchStartedAt:{$exists:true},readyForReviewAt:{$exists:true}}},{$project:{duration:{$subtract:['$readyForReviewAt','$retouchStartedAt']}}},{$group:{_id:null,avgMs:{$avg:'$duration'}}}]),
      this.orders.aggregate<{revenue:number;orders:number;photos:number}>([{$match:{eventId,status:StoreOrderStatus.PAID}},{$group:{_id:null,revenue:{$sum:'$amount'},orders:{$sum:1},photos:{$sum:{$size:'$imageIds'}}}}]),
      this.orders.aggregate<{_id:string;count:number}>([{$match:{eventId}},{$group:{_id:'$status',count:{$sum:1}}}]),
      this.aiJobs.aggregate<{_id:string;count:number}>([{$match:{eventId}},{$group:{_id:'$status',count:{$sum:1}}}]),
      this.guests.countDocuments({eventId,expiresAt:{$gt:new Date()}}),
      this.notifications.aggregate<{_id:string;count:number}>([{$match:{eventId}},{$group:{_id:'$status',count:{$sum:1}}}]),
      this.transfers.aggregate<{_id:string;count:number}>([{$match:{eventId}},{$group:{_id:'$status',count:{$sum:1}}}]),
    ]);
    const topStats=await this.eventsLog.aggregate<{_id:Types.ObjectId;views:number;downloads:number;shares:number;score:number}>([
      {$match:{...logMatch,imageId:{$exists:true},type:{$in:['image_view','download','share']}}},
      {$group:{_id:'$imageId',views:{$sum:{$cond:[{$eq:['$type','image_view']},1,0]}},downloads:{$sum:{$cond:[{$eq:['$type','download']},1,0]}},shares:{$sum:{$cond:[{$eq:['$type','share']},1,0]}}}},
      {$addFields:{score:{$add:['$views',{$multiply:['$downloads',3]},{$multiply:['$shares',2]}]}}},
      {$sort:{score:-1}},{$limit:12},
    ]);
    const topRows=topStats.length?await this.images.find({_id:{$in:topStats.map(row=>row._id)}}).select('_id imageUrl albumId userTakenBy').populate('albumId','title').populate('userTakenBy','name').lean():[];
    const topMap=new Map(topRows.map(row=>[String(row._id),row]));
    const popularPhotos=topStats.map(stat=>({imageId:String(stat._id),views:stat.views,downloads:stat.downloads,shares:stat.shares,score:stat.score,image:topMap.get(String(stat._id))}));    const counts=Object.fromEntries(eventCounts.map(x=>[x._id,x.count]));
    return {eventId:query.eventId,engagement:{...counts,uniqueViewers:uniqueViewers.filter(Boolean).length},photos:{captured:photoCounts,published:publishedCount},daily:daily.map(x=>({date:x._id,count:x.count})),photographers,retouch:{statuses:Object.fromEntries(retouchCounts.map(x=>[x._id,x.count])),averageTurnaroundMinutes:Math.round(((retouchTurnaround[0]?.avgMs||0)/60000)*10)/10},store:{revenue:paid[0]?.revenue||0,paidOrders:paid[0]?.orders||0,purchasedPhotos:paid[0]?.photos||0,statuses:Object.fromEntries(orderCounts.map(x=>[x._id,x.count]))},ai:Object.fromEntries(aiCounts.map(x=>[x._id,x.count])),guests:{activePersonalGalleries:guestCount,notifications:Object.fromEntries(notificationCounts.map(x=>[x._id,x.count]))},transfers:Object.fromEntries(transferCounts.map(x=>[x._id,x.count])),popularPhotos};
  }
}
