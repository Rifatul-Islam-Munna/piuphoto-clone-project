import { Controller, Get, Patch, Post, Body, Query } from '@nestjs/common';
import { RetouchService } from './retouch.service';

@Controller('retouch')
export class RetouchController {
 constructor(private service:RetouchService){}

 @Post()
 create(@Body() body:{eventId:string,imageIds:string[]}){
  return this.service.create(body.eventId,body.imageIds);
 }

 @Get()
 list(@Query('eventId') eventId:string){
  return this.service.list(eventId);
 }

 @Patch('status')
 status(@Body() body:{id:string,status:string}){
  return this.service.updateStatus(body.id,body.status);
 }
}
