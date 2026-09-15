import { Injectable } from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { Model, Types } from 'mongoose';
import { ApiWebhookEndpoint, ApiWebhookEndpointDocument } from './entities/api-webhook-endpoint.entity';
import { ApiWebhookDelivery, ApiWebhookDeliveryDocument } from './entities/api-webhook-delivery.entity';
@Injectable()
export class WorkflowWebhookPublisherService {
  constructor(
    @InjectModel(ApiWebhookEndpoint.name) private readonly endpoints:Model<ApiWebhookEndpointDocument>,
    @InjectModel(ApiWebhookDelivery.name) private readonly deliveries:Model<ApiWebhookDeliveryDocument>,
  ){}
  async publish(eventId:string,eventType:string,payload:Record<string,unknown>){
    if(!Types.ObjectId.isValid(eventId)) return 0;
    const rows=await this.endpoints.find({eventId:new Types.ObjectId(eventId),active:true,eventTypes:eventType}).select('_id').lean();
    if(!rows.length) return 0;
    const inserted=await this.deliveries.insertMany(rows.map(row=>({endpointId:row._id,eventId:new Types.ObjectId(eventId),eventType,payload,status:'pending',attempts:0,nextAttemptAt:new Date()})),{ordered:false}).catch(()=>[]);
    return Array.isArray(inserted)?inserted.length:0;
  }
}
