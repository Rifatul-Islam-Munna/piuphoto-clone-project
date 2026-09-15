import { Injectable } from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { Model, Types } from 'mongoose';
import { RetouchJob } from './retouch.entity';

@Injectable()
export class RetouchService {
 constructor(@InjectModel(RetouchJob.name) private jobs: Model<RetouchJob>) {}

 create(eventId:string,imageIds:string[]){
  return this.jobs.create({eventId:new Types.ObjectId(eventId),imageIds:imageIds.map(id=>new Types.ObjectId(id))});
 }

 updateStatus(id:string,status:string){
  return this.jobs.findByIdAndUpdate(id,{status},{new:true});
 }

 list(eventId:string){
  return this.jobs.find({eventId:new Types.ObjectId(eventId)}).sort({createdAt:-1});
 }
}
