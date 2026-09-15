import { BadRequestException, Body, Controller, Get, Headers, Param, Patch, Post, Query, UploadedFile, UseInterceptors } from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { ApiConsumes, ApiSecurity, ApiTags } from '@nestjs/swagger';
import { diskStorage, memoryStorage } from 'multer';
import { existsSync, mkdirSync } from 'fs';
import { unlink } from 'fs/promises';
import { extname, join } from 'path';
import { cwd } from 'process';
import { AlbumService } from '../album/album.service';
import { AnalyticsService } from '../analytics/analytics.service';
import { EventImageService } from '../event-image/event-image.service';
import { EventService } from '../event/event.service';
import { GalleryAccessService } from '../gallery-access/gallery-access.service';
import { GuestGalleryService } from '../guest-gallery/guest-gallery.service';
import { ImageService } from '../image/image.service';
import {
  ApiAnalyzeDto, ApiCreateCategoryDto, ApiCreateEventDto, ApiEnhanceDto, ApiFaceSearchDto, ApiMobileSearchDto,
  ApiGallerySettingsDto, ApiUpdateCategoryDto, ApiUpdateEventDto,
  ApiUploadDto, ApiUploadFileDto, CreateApiWebhookDto,
} from './dto/external-api.dto';
import { ExternalApiService } from './external-api.service';

const externalUploadOptions = {
  storage: diskStorage({
    destination: (_req, _file, cb) => {
      const dir = join(cwd(), 'uploads');
      if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
      cb(null, dir);
    },
    filename: (_req, file, cb) => cb(null, `${Date.now()}-${Math.round(Math.random()*1e9)}${extname(file.originalname)}`),
  }),
  limits: { fileSize: 256 * 1024 * 1024 },
  fileFilter: (_req, file, cb) => {
    const ext = extname(file.originalname || '').toLowerCase();
    const allowed = new Set(['.jpg','.jpeg','.png','.webp','.heic','.heif','.tif','.tiff','.dng','.arw','.cr2','.cr3','.nef','.nrw','.raf','.rw2','.orf','.pef','.mp4','.mov','.webm','.mkv']);
    if (!allowed.has(ext)) return cb(new BadRequestException('Unsupported photo/video format'), false);
    cb(null, true);
  },
};
const externalFaceUploadOptions = {
  storage: memoryStorage(),
  limits: { fileSize: 12 * 1024 * 1024 },
  fileFilter: (_req, file, cb) => {
    const allowed = new Set(['image/jpeg','image/png','image/webp','image/heic','image/heif']);
    if (!allowed.has(String(file.mimetype || '').toLowerCase())) {
      return cb(new BadRequestException('Selfie must be an image'), false);
    }
    cb(null, true);
  },
};
@ApiTags('External API v1')
@ApiSecurity('x-api-key')
@Controller('v1')
export class ExternalV1Controller {
  constructor(
    private readonly api:ExternalApiService,
    private readonly eventService:EventService,
    private readonly eventImages:EventImageService,
    private readonly analytics:AnalyticsService,
    private readonly albums:AlbumService,
    private readonly gallery:GalleryAccessService,
    private readonly guests:GuestGalleryService,
    private readonly imageService:ImageService,
  ){}

  @Get('setup/events/:eventId')
  async getSetupEvent(@Headers('x-api-key') key:string,@Param('eventId') eventId:string){
    await this.api.authenticate(key,'setup:read',eventId); return this.api.viewerEvent(eventId);
  }
  @Post('setup/events')
  async createEvent(@Headers('x-api-key') key:string,@Body() body:ApiCreateEventDto){
    const actor=await this.api.authenticate(key,'setup:write');
    const result:any=await this.eventService.create({...body,userId:actor.userId} as any);
    const eventId=String(result?.data?._id||result?._id||'');
    return {...result,galleryPath:eventId?`/event/${eventId}`:undefined,eventId:eventId||undefined};
  }

  @Patch('setup/events/:eventId')
  async updateEvent(@Headers('x-api-key') key:string,@Param('eventId') eventId:string,@Body() body:ApiUpdateEventDto){
    const actor=await this.api.authenticate(key,'setup:write',eventId);
    return this.eventService.update(eventId,body as any,actor.userId);
  }

  @Get('setup/events/:eventId/gallery')
  async getGallery(@Headers('x-api-key') key:string,@Param('eventId') eventId:string){
    const actor=await this.api.authenticate(key,'setup:read',eventId);
    return this.gallery.getSettings(eventId,actor.userId);
  }

  @Patch('setup/events/:eventId/gallery')
  async updateGallery(@Headers('x-api-key') key:string,@Param('eventId') eventId:string,@Body() body:ApiGallerySettingsDto){
    const actor=await this.api.authenticate(key,'setup:write',eventId);
    return this.gallery.updateSettings({eventId,...body} as any,actor.userId);
  }
  @Post('setup/events/:eventId/categories')
  async createCategory(@Headers('x-api-key') key:string,@Param('eventId') eventId:string,@Body() body:ApiCreateCategoryDto){
    const actor=await this.api.authenticate(key,'setup:write',eventId);
    return this.albums.create({eventId,...body},actor.userId);
  }

  @Patch('setup/events/:eventId/categories/:albumId')
  async updateCategory(@Headers('x-api-key') key:string,@Param('eventId') eventId:string,@Param('albumId') albumId:string,@Body() body:ApiUpdateCategoryDto){
    const actor=await this.api.authenticate(key,'setup:write',eventId);
    return this.albums.update(albumId,body,actor.userId);
  }

  @Get('viewer/events/:eventId')
  async event(@Headers('x-api-key') key:string,@Param('eventId') eventId:string){
    await this.api.authenticate(key,'viewer:read',eventId); return this.api.viewerEvent(eventId);
  }

  @Get('viewer/events/:eventId/media')
  async media(@Headers('x-api-key') key:string,@Param('eventId') eventId:string,@Query('albumId') albumId?:string){
    await this.api.authenticate(key,'viewer:read',eventId); return this.api.viewerImages(eventId,albumId);
  }

  @Get('viewer/events/:eventId/albums')
  async viewerAlbums(@Headers('x-api-key') key:string,@Param('eventId') eventId:string){
    const actor=await this.api.authenticate(key,'viewer:read',eventId);
    return this.albums.findAll({eventId},actor.userId);
  }
  @Post('viewer/face-search')
  @ApiConsumes('multipart/form-data')
  @UseInterceptors(FileInterceptor('file', externalFaceUploadOptions))
  async viewerFaceSearch(@Headers('x-api-key') key:string,@Body() body:ApiFaceSearchDto,@UploadedFile() file:Express.Multer.File){
    if(!file?.buffer) throw new BadRequestException('Selfie image is required');
    const actor=await this.api.authenticate(key,'viewer:read',body.eventId);
    return this.eventImages.findMyPictures(file,{eventId:body.eventId,albumId:body.albumId} as any,actor.userId,undefined,false);
  }

  @Get('viewer/events/:eventId/analytics')
  async viewerAnalytics(@Headers('x-api-key') key:string,@Param('eventId') eventId:string,@Query('from') from?:string,@Query('to') to?:string){
    const actor=await this.api.authenticate(key,'viewer:read',eventId);
    return this.analytics.summary({eventId,from,to},actor.userId);
  }
  @Post('viewer/mobile-search')
  async mobileSearch(@Headers('x-api-key') key:string,@Body() body:ApiMobileSearchDto){
    await this.api.authenticate(key,'viewer:read',body.eventId);
    return this.guests.personalByMobile(body.eventId,body.mobile,body.albumId);
  }
  @Post('upload')
  async upload(@Headers('x-api-key') key:string,@Body() body:ApiUploadDto){
    const actor=await this.api.authenticate(key,'upload:write',body.eventId);
    const result:any=await this.eventImages.create({eventId:body.eventId,albumId:body.albumId,imageUrl:body.imageUrl,isEnhanced:false,mediaType:body.mediaType,clientTransferId:body.idempotencyKey} as any,actor.userId);
    const row=result?.data;
    return {...result,eventImageId:row?._id?String(row._id):undefined,idempotencyKey:body.idempotencyKey,status:row?.isPublished!==false?'published':'processing'};
  }

  @Post('upload/file')
  @UseInterceptors(FileInterceptor('file', externalUploadOptions))
  async uploadFile(@Headers('x-api-key') key:string,@Body() body:ApiUploadFileDto,@UploadedFile() file:any){
    if(!file) throw new BadRequestException('File is required');
    try{
      const actor=await this.api.authenticate(key,'upload:write',body.eventId);
      const uploaded=await this.imageService.uploadImage(file);
      const result:any=await this.eventImages.create({eventId:body.eventId,albumId:body.albumId,imageUrl:uploaded.url,isEnhanced:false,mediaType:body.mediaType,clientTransferId:body.idempotencyKey} as any,actor.userId);
      const row=result?.data;
      return {...result,eventImageId:row?._id?String(row._id):undefined,idempotencyKey:body.idempotencyKey,status:row?.isPublished!==false?'published':'processing'};
    }catch(error){
      if(file?.path) await unlink(file.path).catch(()=>undefined);
      throw error;
    }
  }
  @Get('upload/status/:imageId')
  async uploadStatus(@Headers('x-api-key') key:string,@Param('imageId') imageId:string,@Query('eventId') eventId:string){
    await this.api.authenticate(key,'upload:write',eventId);
    return this.api.uploadStatus(eventId,imageId);
  }

  @Post('ai/enhance')
  async enhance(@Headers('x-api-key') key:string,@Body() body:ApiEnhanceDto){
    const actor=await this.api.authenticate(key,'ai:write',body.eventId);
    return this.eventImages.enhanceExisting(body.imageId,actor.userId,undefined,body.prompt);
  }

  @Post('ai/cartoon')
  async cartoon(@Headers('x-api-key') key:string,@Body() body:ApiEnhanceDto){
    const actor=await this.api.authenticate(key,'ai:write',body.eventId);
    const prompt=body.prompt?.trim() || 'Create a polished illustrated cartoon version while preserving the same people, pose, clothing, scene composition and recognizable non-sensitive visual details. Keep it tasteful and event-ready.';
    return this.eventImages.enhanceExisting(body.imageId,actor.userId,undefined,prompt);
  }
  @Post('ai/review')
  async analyze(@Headers('x-api-key') key:string,@Body() body:ApiAnalyzeDto){
    const actor=await this.api.authenticate(key,'ai:write',body.eventId);
    return this.eventImages.analyzeMedia(body.ids,actor.userId);
  }
  @Post('ai/face-search')
  @ApiConsumes('multipart/form-data')
  @UseInterceptors(FileInterceptor('file', externalFaceUploadOptions))
  async faceSearch(
    @Headers('x-api-key') key:string,
    @Body() body:ApiFaceSearchDto,
    @UploadedFile() file:Express.Multer.File,
  ){
    if(!file?.buffer) throw new BadRequestException('Selfie image is required');
    const actor=await this.api.authenticate(key,'ai:read',body.eventId);
    return this.eventImages.findMyPictures(
      file,
      {eventId:body.eventId,albumId:body.albumId} as any,
      actor.userId,
      undefined,
      false,
    );
  }
  @Get('ai/search')
  async search(@Headers('x-api-key') key:string,@Query('eventId') eventId:string,@Query('q') q:string,@Query('type') type='all',@Query('limit') limit='200'){
    const actor=await this.api.authenticate(key,'ai:read',eventId);
    return this.eventImages.aiSearch(eventId,q,type,Number(limit)||200,actor.userId);
  }

  @Get('analytics')
  async analyticsSummary(@Headers('x-api-key') key:string,@Query('eventId') eventId:string,@Query('from') from?:string,@Query('to') to?:string){
    const actor=await this.api.authenticate(key,'analytics:read',eventId);
    return this.analytics.summary({eventId,from,to},actor.userId);
  }

  @Post('webhooks')
  async webhook(@Headers('x-api-key') key:string,@Body() body:CreateApiWebhookDto){
    const actor=await this.api.authenticate(key,'webhooks:write',body.eventId);
    return this.api.createWebhook(body,actor.userId);
  }
}
