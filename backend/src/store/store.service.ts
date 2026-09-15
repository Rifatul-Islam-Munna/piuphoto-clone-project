import { ForbiddenException, HttpException, Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { InjectModel } from '@nestjs/mongoose';
import axios from 'axios';
import { createCipheriv, createDecipheriv, createHash, createHmac, randomBytes, timingSafeEqual } from 'crypto';
import { Model, Types } from 'mongoose';
import sharp from 'sharp';
import { EventMemberService } from '../event-member/event-member.service';
import { Event, EventDocument } from '../event/entities/event.entity';
import { EventImage, EventImageDocument } from '../event-image/entities/event-image.entity';
import { NotificationService } from '../notification/notification.service';
import { StoreCheckoutDto, StoreOrderQueryDto, StoreSaleDto, StoreSettingsDto, StoreVerifyDto } from './dto/store.dto';
import { StoreOrder, StoreOrderDocument, StoreOrderStatus } from './entities/store-order.entity';
import { StoreSettings, StoreSettingsDocument } from './entities/store-settings.entity';

@Injectable()
export class StoreService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(StoreService.name);
  private deliveryWorker?: ReturnType<typeof setInterval>;
  private paymentWorker?: ReturnType<typeof setInterval>;
  constructor(
    @InjectModel(StoreSettings.name) private readonly settings: Model<StoreSettingsDocument>,
    @InjectModel(StoreOrder.name) private readonly orders: Model<StoreOrderDocument>,
    @InjectModel(Event.name) private readonly events: Model<EventDocument>,
    @InjectModel(EventImage.name) private readonly images: Model<EventImageDocument>,
    private readonly members: EventMemberService,
    private readonly config: ConfigService,
    private readonly notifier: NotificationService,
  ) {}
  onModuleInit() {
    this.deliveryWorker = setInterval(() => void this.flushPendingDeliveries(), 30000);
    const reconcileMs = Math.max(Number(this.config.get<string>('STRIPE_RECONCILE_SECONDS')) || 60, 15) * 1000;
    this.paymentWorker = setInterval(() => void this.reconcileStripePayments(), reconcileMs);
    this.deliveryWorker.unref?.();
    this.paymentWorker.unref?.();
    void this.reconcileStripePayments();
    void this.flushPendingDeliveries();
  }
  onModuleDestroy() {
    if (this.deliveryWorker) clearInterval(this.deliveryWorker);
    if (this.paymentWorker) clearInterval(this.paymentWorker);
  }
  private async flushPendingDeliveries() {
    if (!this.notifier.emailConfigured() && !this.notifier.whatsappConfigured()) return;
    try {
      const rows=await this.orders.find({status:StoreOrderStatus.PAID,deliverySentAt:{$exists:false},downloadTokenCipher:{$exists:true},$or:[{deliveryAttempts:{$lt:5}},{deliveryAttempts:{$exists:false}}]}).select('+downloadTokenCipher').sort({paidAt:1}).limit(20).exec();
      for(const order of rows){ if(order.downloadTokenCipher) await this.sendDelivery(order,this.decrypt(order.downloadTokenCipher)); }
    } catch(error) {
      this.logger.warn(`store-delivery-worker ${String(error)}`);
    }
  }
  private async stripeGet<T = any>(path: string, params?: Record<string, string>) {
    const response = await axios.get<T>(`https://api.stripe.com/v1/${path}`, {
      headers: { Authorization: `Bearer ${this.stripeKey()}` },
      params,
      timeout: 15000,
    });
    return response.data;
  }

  private async reconcileStripePayments() {
    let key = '';
    try { key = this.stripeKey(); } catch { return; }
    if (!key) return;
    try {
      const pending = await this.orders.find({
        status: StoreOrderStatus.PENDING,
        stripeSessionId: { $exists: true, $ne: '' },
      }).sort({ lastPaymentCheckAt: 1, createdAt: 1 }).limit(20).exec();
      for (const order of pending) {
        const session = await this.stripeGet<any>(`checkout/sessions/${encodeURIComponent(String(order.stripeSessionId))}`);
        await this.orders.updateOne({ _id: order._id }, { $set: { lastPaymentCheckAt: new Date() } });
        if (session.payment_status === 'paid') {
          await this.ensurePaid(order, typeof session.payment_intent === 'string' ? session.payment_intent : undefined);
        } else if (session.status === 'expired') {
          await this.orders.updateOne({ _id: order._id, status: StoreOrderStatus.PENDING }, { $set: { status: StoreOrderStatus.FAILED } });
        }
      }

      const paid = await this.orders.find({
        status: StoreOrderStatus.PAID,
        paymentIntentId: { $exists: true, $ne: '' },
      }).sort({ lastPaymentCheckAt: 1, paidAt: 1 }).limit(20).exec();
      for (const order of paid) {
        const intent = await this.stripeGet<any>(`payment_intents/${encodeURIComponent(String(order.paymentIntentId))}`, { 'expand[]': 'latest_charge' });
        const charge = intent?.latest_charge;
        const refunded = Boolean(charge && typeof charge === 'object' && (charge.refunded === true || Number(charge.amount_refunded || 0) > 0));
        if (refunded) {
          await this.orders.updateOne({ _id: order._id, status: StoreOrderStatus.PAID }, {
            $set: { status: StoreOrderStatus.REFUNDED, refundedAt: new Date(), lastPaymentCheckAt: new Date() },
            $unset: { downloadTokenHash: '', downloadTokenCipher: '', downloadExpiresAt: '' },
          });
        } else {
          await this.orders.updateOne({ _id: order._id }, { $set: { lastPaymentCheckAt: new Date() } });
        }
      }
    } catch (error) {
      this.logger.warn(`stripe-reconcile ${String(error)}`);
    }
  }
  private oid(id: string) { if (!Types.ObjectId.isValid(id)) throw new HttpException('Invalid id', 400); return new Types.ObjectId(id); }
  private stripeKey() { const value=this.config.get<string>('STRIPE_SECRET_KEY')?.trim(); if(!value) throw new HttpException('Stripe secret key missing',500); return value; }
  private frontendUrl() { return (this.config.get<string>('PUBLIC_APP_URL') || this.config.get<string>('CORS_ORIGIN')?.split(',')[0] || 'http://localhost:8080').replace(/\/$/,''); }
  private tokenSecret() { return createHash('sha256').update(this.config.get<string>('STORE_TOKEN_SECRET') || this.config.get<string>('ACCESS_TOKEN') || 'change-store-token-secret').digest(); }
  private encrypt(value:string){ const iv=randomBytes(12); const cipher=createCipheriv('aes-256-gcm',this.tokenSecret(),iv); const body=Buffer.concat([cipher.update(value,'utf8'),cipher.final()]); return Buffer.concat([iv,cipher.getAuthTag(),body]).toString('base64url'); }
  private decrypt(value:string){ const body=Buffer.from(value,'base64url'); const iv=body.subarray(0,12); const tag=body.subarray(12,28); const data=body.subarray(28); const d=createDecipheriv('aes-256-gcm',this.tokenSecret(),iv); d.setAuthTag(tag); return Buffer.concat([d.update(data),d.final()]).toString('utf8'); }
  private hash(value:string){ return createHash('sha256').update(value).digest('hex'); }
  private async getSettings(eventId:string){ return this.settings.findOneAndUpdate({eventId:this.oid(eventId)},{$setOnInsert:{eventId:this.oid(eventId),enabled:false,currency:'USD',singlePhotoPrice:5,bundlePrice:0,bundleMinPhotos:10,downloadExpiresHours:72,watermarkedPreview:true,saleAlbumIds:[]}},{upsert:true,new:true,setDefaultsOnInsert:true}).lean(); }

  async publicCatalog(eventId:string, albumId?:string){
    const config=await this.getSettings(eventId);
    const event=await this.events.findOne({_id:this.oid(eventId),isActive:true,isPublished:true}).select('title description branding').lean();
    if(!event || !config?.enabled) throw new HttpException('Store is not available',404);
    const allowedAlbums=(config.saleAlbumIds||[]).map(String);
    if(albumId && allowedAlbums.length && !allowedAlbums.includes(albumId)) throw new HttpException('This category is not for sale',404);
    const rows=await this.images.find({eventId:this.oid(eventId),isPublished:{$ne:false},isForSale:{$ne:false},mediaType:{$ne:'video'},...(albumId?{albumId:this.oid(albumId)}:allowedAlbums.length?{albumId:{$in:allowedAlbums.map(id=>this.oid(id))}}:{})}).select('_id albumId createdAt isEnhanced').sort({createdAt:-1}).limit(1000).lean();
    return { event:{_id:String(event._id),title:event.title,description:event.description,branding:event.branding||{}}, settings:{currency:config.currency,singlePhotoPrice:config.singlePhotoPrice,bundlePrice:config.bundlePrice,bundleMinPhotos:config.bundleMinPhotos,termsText:config.termsText}, data:rows.map(row=>({_id:String(row._id),albumId:row.albumId?String(row.albumId):undefined,isEnhanced:row.isEnhanced,previewUrl:`/store/public/preview?eventId=${eventId}&imageId=${row._id}`})), totalItems:rows.length };
  }

  async preview(eventId:string,imageId:string){
    const config=await this.getSettings(eventId); if(!config?.enabled) throw new HttpException('Store unavailable',404);
    const image=await this.images.findOne({_id:this.oid(imageId),eventId:this.oid(eventId),isPublished:{$ne:false},isForSale:{$ne:false},mediaType:{$ne:'video'}}).select('imageUrl albumId').lean(); if(!image) throw new HttpException('Photo not found',404);
    const allowedAlbums=(config.saleAlbumIds||[]).map(String); if(allowedAlbums.length && (!image.albumId || !allowedAlbums.includes(String(image.albumId)))) throw new HttpException('Photo is not available for sale',404);
    const response=await axios.get<ArrayBuffer>(image.imageUrl,{responseType:'arraybuffer',timeout:30000,maxContentLength:60*1024*1024});
    let pipeline=sharp(Buffer.from(response.data)).rotate().resize({width:1200,withoutEnlargement:true});
    if(config.watermarkedPreview!==false){ const svg=Buffer.from('<svg width="600" height="120"><text x="300" y="72" text-anchor="middle" font-size="48" font-family="Arial" fill="white" fill-opacity="0.55">PREVIEW</text></svg>'); pipeline=pipeline.composite([{input:svg,gravity:'center'}]); }
    return pipeline.jpeg({quality:64}).toBuffer();
  }

  private price(config:StoreSettingsDocument|Record<string,any>, count:number){
    if(config.bundlePrice>0 && count>=config.bundleMinPhotos) return Number(config.bundlePrice);
    return Math.round(Number(config.singlePhotoPrice)*count*100)/100;
  }

  async checkout(dto:StoreCheckoutDto){
    const config=await this.getSettings(dto.eventId); if(!config?.enabled) throw new HttpException('Store is disabled',400);
    const unique=[...new Set(dto.imageIds)]; const allowedAlbums=(config.saleAlbumIds||[]).map(String);
    const rows=await this.images.find({_id:{$in:unique.map(id=>this.oid(id))},eventId:this.oid(dto.eventId),isPublished:{$ne:false},isForSale:{$ne:false},mediaType:{$ne:'video'},...(allowedAlbums.length?{albumId:{$in:allowedAlbums.map(id=>this.oid(id))}}:{})}).select('_id').lean();
    if(rows.length!==unique.length) throw new HttpException('One or more photos are unavailable',400);
    const amount=this.price(config,rows.length); if(amount<=0) throw new HttpException('Invalid store price',400);
    const orderSeed={orderNo:`ORD-${Date.now().toString(36).toUpperCase()}-${randomBytes(3).toString('hex').toUpperCase()}`,eventId:this.oid(dto.eventId),imageIds:rows.map(x=>x._id),email:dto.email.trim().toLowerCase(),whatsapp:dto.whatsapp?.trim(),amount,currency:config.currency,status:StoreOrderStatus.PENDING};
    const checkoutKey=dto.idempotencyKey?.trim();
    let order:StoreOrderDocument;
    if(checkoutKey){
      try{
        order=await this.orders.findOneAndUpdate({checkoutIdempotencyKey:checkoutKey},{$setOnInsert:{...orderSeed,checkoutIdempotencyKey:checkoutKey}},{upsert:true,new:true,setDefaultsOnInsert:true}).exec() as StoreOrderDocument;
      }catch(error:any){
        if(error?.code!==11000) throw error;
        order=await this.orders.findOne({checkoutIdempotencyKey:checkoutKey}).exec() as StoreOrderDocument;
      }
      if(!order) throw new HttpException('Checkout could not be resumed',409);
      const requestedIds=rows.map(x=>String(x._id)).sort().join(',');
      const existingIds=(order.imageIds||[]).map(String).sort().join(',');
      if(String(order.eventId)!==dto.eventId||order.email!==dto.email.trim().toLowerCase()||Number(order.amount)!==Number(amount)||existingIds!==requestedIds){
        throw new HttpException('Idempotency key was already used for a different checkout',409);
      }
      if(order.status===StoreOrderStatus.PAID && order.stripeSessionId){
        return {orderId:String(order._id),orderNo:order.orderNo,sessionId:order.stripeSessionId,url:`${this.frontendUrl()}/#/store/order/${order._id}?session_id=${encodeURIComponent(order.stripeSessionId)}`,amount:order.amount,currency:order.currency,idempotent:true,status:'paid'};
      }
      if(order.stripeSessionId && order.stripeCheckoutUrl && order.status===StoreOrderStatus.PENDING){
        return {orderId:String(order._id),orderNo:order.orderNo,sessionId:order.stripeSessionId,url:order.stripeCheckoutUrl,amount:order.amount,currency:order.currency,idempotent:true};
      }
      if(order.status===StoreOrderStatus.FAILED){ order.status=StoreOrderStatus.PENDING; await order.save(); }
    }else{
      order=await this.orders.create(orderSeed);
    }
    const params=new URLSearchParams();
    params.append('mode','payment'); params.append('success_url',`${this.frontendUrl()}/#/store/order/${order._id}?session_id={CHECKOUT_SESSION_ID}`); params.append('cancel_url',`${this.frontendUrl()}/#/store/${dto.eventId}?checkout=cancel`); params.append('customer_email',order.email); params.append('client_reference_id',String(order._id)); params.append('metadata[orderId]',String(order._id)); params.append('metadata[eventId]',dto.eventId); params.append('line_items[0][price_data][currency]',String(config.currency||'USD').toLowerCase()); params.append('line_items[0][price_data][product_data][name]',`${rows.length} digital event photo${rows.length===1?'':'s'}`); params.append('line_items[0][price_data][unit_amount]',String(Math.round(amount*100))); params.append('line_items[0][quantity]','1');
    try{
      const headers:Record<string,string>={Authorization:`Bearer ${this.stripeKey()}`,'Content-Type':'application/x-www-form-urlencoded'};
      if(checkoutKey) headers['Idempotency-Key']=`airpix-store-${checkoutKey}`;
      const {data}=await axios.post<{id:string;url?:string}>('https://api.stripe.com/v1/checkout/sessions',params.toString(),{headers,timeout:20000});
      if(!data.id||!data.url) throw new Error('Invalid Stripe response');
      order.stripeSessionId=data.id; order.stripeCheckoutUrl=data.url; order.status=StoreOrderStatus.PENDING; await order.save();
      return {orderId:String(order._id),orderNo:order.orderNo,sessionId:data.id,url:data.url,amount,currency:config.currency,idempotent:false};
    }catch(error:any){
      await this.orders.updateOne({_id:order._id},{$set:{status:StoreOrderStatus.FAILED}});
      throw new HttpException(error?.response?.data?.error?.message||error?.message||'Checkout failed',400);
    }
  }
  private verifyStripeSignature(rawBody:Buffer|undefined, signatureHeader?:string){
    const secret=this.config.get<string>('STRIPE_WEBHOOK_SECRET')?.trim();
    if(!secret) return false;
    if(!rawBody||!signatureHeader) throw new ForbiddenException('Invalid Stripe webhook');
    const parts=Object.fromEntries(signatureHeader.split(',').map(item=>item.split('=',2)));
    const timestamp=parts.t; const provided=parts.v1;
    if(!timestamp||!provided) throw new ForbiddenException('Invalid Stripe signature');
    if(Math.abs(Math.floor(Date.now()/1000)-Number(timestamp))>300) throw new ForbiddenException('Expired Stripe webhook');
    const expected=createHmac('sha256',secret).update(`${timestamp}.${rawBody.toString('utf8')}`).digest('hex');
    const a=Buffer.from(provided,'hex'); const b=Buffer.from(expected,'hex');
    if(a.length!==b.length||!timingSafeEqual(a,b)) throw new ForbiddenException('Invalid Stripe signature');
    return true;
  }

  private async ensurePaid(order:StoreOrderDocument|any, paymentIntentId?:string){
    let full=await this.orders.findById(order._id).select('+downloadTokenCipher').exec();
    if(!full) throw new HttpException('Order not found',404);
    if(full.status===StoreOrderStatus.REFUNDED) throw new HttpException('Order refunded',400);
    if(full.status!==StoreOrderStatus.PAID || !full.downloadTokenCipher){
      const config=await this.getSettings(String(full.eventId));
      const tokenCandidate=randomBytes(32).toString('base64url');
      const set:Record<string,unknown>={status:StoreOrderStatus.PAID,paidAt:full.paidAt||new Date(),downloadTokenHash:this.hash(tokenCandidate),downloadTokenCipher:this.encrypt(tokenCandidate),downloadExpiresAt:new Date(Date.now()+(config?.downloadExpiresHours||72)*3600000)};
      if(paymentIntentId) set.paymentIntentId=paymentIntentId;
      const claimed=await this.orders.findOneAndUpdate({_id:full._id,status:{$ne:StoreOrderStatus.REFUNDED},$or:[{status:{$ne:StoreOrderStatus.PAID}},{downloadTokenCipher:{$exists:false}},{downloadTokenCipher:null}]},{$set:set},{new:true}).select('+downloadTokenCipher').exec();
      full=claimed||await this.orders.findById(order._id).select('+downloadTokenCipher').exec();
      if(!full) throw new HttpException('Order not found',404);
      if(full.status===StoreOrderStatus.REFUNDED) throw new HttpException('Order refunded',400);
    }else if(paymentIntentId && !full.paymentIntentId){
      await this.orders.updateOne({_id:full._id,status:StoreOrderStatus.PAID},{$set:{paymentIntentId}});
      full.paymentIntentId=paymentIntentId;
    }
    if(!full.downloadTokenCipher) throw new HttpException('Order delivery token is unavailable',500);
    const token=this.decrypt(full.downloadTokenCipher);
    await this.sendDelivery(full,token);
    return {order:full,token};
  }

  private async sendDelivery(order:StoreOrderDocument, token:string){
    if(order.deliverySentAt) return;
    if(!this.notifier.emailConfigured() && !this.notifier.whatsappConfigured()) return;
    const stale=new Date(Date.now()-2*60*1000);
    const claimed=await this.orders.findOneAndUpdate({_id:order._id,deliverySentAt:{$exists:false},$or:[{deliverySendingAt:{$exists:false}},{deliverySendingAt:null},{deliverySendingAt:{$lt:stale}}]},{$set:{deliverySendingAt:new Date()},$inc:{deliveryAttempts:1}},{new:true}).exec();
    if(!claimed) return;
    try{
      const link=`${this.frontendUrl()}/#/store/order/${order._id}?token=${encodeURIComponent(token)}`;
      const event=await this.events.findById(order.eventId).select('title').lean();
      await this.notifier.sendStoreDelivery({
        email: order.email,
        whatsapp: order.whatsapp,
        eventTitle: event?.title || 'Your event',
        link,
        photoCount: order.imageIds.length,
      });
      await this.orders.updateOne({_id:order._id,deliverySentAt:{$exists:false}},{$set:{deliverySentAt:new Date()},$unset:{deliverySendingAt:'',deliveryError:''}});
    }catch(error){
      this.logger.warn(`store-delivery-failed order=${order._id} ${String(error)}`);
      await this.orders.updateOne({_id:order._id},{$set:{deliveryError:error instanceof Error?error.message:String(error)},$unset:{deliverySendingAt:''}});
    }
  }
  async webhook(rawBody:Buffer|undefined, signature:string|undefined, body:any){
    const verified=this.verifyStripeSignature(rawBody,signature);
    if(!verified){
      return {received:true,verified:false,mode:'stripe-api-reconciliation'};
    }
    const event=body||JSON.parse(rawBody!.toString('utf8')); const object=event?.data?.object||{};
    if(['checkout.session.completed','checkout.session.async_payment_succeeded'].includes(event.type)){
      const order=await this.orders.findOne({$or:[{stripeSessionId:object.id},{_id:Types.ObjectId.isValid(object?.metadata?.orderId||'')?this.oid(object.metadata.orderId):undefined}].filter((x:any)=>Object.values(x)[0]!==undefined)}).exec();
      if(order && (object.payment_status==='paid'||event.type.endsWith('succeeded'))) await this.ensurePaid(order,typeof object.payment_intent==='string'?object.payment_intent:undefined);
    }
    if(event.type==='charge.refunded' && object.payment_intent){ await this.orders.updateMany({paymentIntentId:object.payment_intent},{$set:{status:StoreOrderStatus.REFUNDED,refundedAt:new Date(),lastPaymentCheckAt:new Date()},$unset:{downloadTokenHash:'',downloadTokenCipher:'',downloadExpiresAt:''}}); }
    return {received:true,verified:true};
  }

  async verifyCheckout(dto:StoreVerifyDto){
    const order=await this.orders.findOne({_id:this.oid(dto.orderId),stripeSessionId:dto.sessionId}).exec(); if(!order) throw new HttpException('Order not found',404);
    const {data}=await axios.get<any>(`https://api.stripe.com/v1/checkout/sessions/${encodeURIComponent(dto.sessionId)}`,{headers:{Authorization:`Bearer ${this.stripeKey()}`},timeout:15000}); if(data.payment_status!=='paid') throw new HttpException('Payment is not completed yet',400); const paid=await this.ensurePaid(order,typeof data.payment_intent==='string'?data.payment_intent:undefined); return {status:'paid',orderId:String(order._id),orderNo:order.orderNo,downloadToken:paid.token,expiresAt:paid.order.downloadExpiresAt};
  }

  async orderByToken(orderId:string,token:string){
    const order:any=await this.orders.findOne({_id:this.oid(orderId),downloadTokenHash:this.hash(token),status:StoreOrderStatus.PAID,downloadExpiresAt:{$gt:new Date()}}).populate('eventId','title').populate('imageIds','_id createdAt').lean();
    if(!order) throw new ForbiddenException('Order download link is invalid or expired');
    const eventId=String(order.eventId?._id||order.eventId);
    const safeImages=(order.imageIds||[]).map((image:any)=>({
      _id:String(image._id),createdAt:image.createdAt,
      previewUrl:`/store/public/preview?eventId=${eventId}&imageId=${image._id}`,
      downloadUrl:`/store/public/download?orderId=${encodeURIComponent(orderId)}&imageId=${encodeURIComponent(String(image._id))}&token=${encodeURIComponent(token)}`,
    }));
    return {data:{...order,imageIds:safeImages}};
  }
  async downloadPurchased(orderId:string,token:string,imageId:string){
    const order=await this.orders.findOne({_id:this.oid(orderId),downloadTokenHash:this.hash(token),status:StoreOrderStatus.PAID,downloadExpiresAt:{$gt:new Date()},imageIds:this.oid(imageId)}).select('eventId').lean();
    if(!order) throw new ForbiddenException('Purchased file access is invalid or expired');
    const image=await this.images.findOne({_id:this.oid(imageId),eventId:order.eventId}).select('imageUrl').lean();
    if(!image) throw new HttpException('Purchased photo not found',404);
    const response=await axios.get<ArrayBuffer>(image.imageUrl,{responseType:'arraybuffer',timeout:60000,maxContentLength:256*1024*1024});
    return {buffer:Buffer.from(response.data),contentType:String(response.headers['content-type']||'application/octet-stream'),filename:`photo-${String(image._id).slice(-8)}`};
  }
  async settingsForPlanner(eventId:string,userId?:string,role?:string){ await this.members.assertCanManage(eventId,userId,role); return {data:await this.getSettings(eventId)}; }
  async updateSettings(dto:StoreSettingsDto,userId?:string,role?:string){ await this.members.assertCanManage(dto.eventId,userId,role); const set:{[key:string]:unknown}={}; for(const key of ['enabled','currency','singlePhotoPrice','bundlePrice','bundleMinPhotos','downloadExpiresHours','watermarkedPreview','termsText','saleAlbumIds'] as const){ if(dto[key]!==undefined) set[key]=key==='currency'?String(dto[key]).toUpperCase():key==='saleAlbumIds'?(dto.saleAlbumIds||[]).map(id=>this.oid(id)):dto[key]; } const data=await this.settings.findOneAndUpdate({eventId:this.oid(dto.eventId)},{$set:set,$setOnInsert:{eventId:this.oid(dto.eventId)}},{upsert:true,new:true,setDefaultsOnInsert:true}).lean(); return {message:'Store settings updated',data}; }
  async salePhotosForPlanner(eventId:string,userId?:string,role?:string){ await this.members.assertCanManage(eventId,userId,role); const data=await this.images.find({eventId:this.oid(eventId),isPublished:{$ne:false},mediaType:{$ne:'video'}}).select('_id imageUrl albumId isForSale createdAt').populate('albumId','title').sort({createdAt:-1}).limit(1000).lean(); return {data,totalItems:data.length}; }
  async updatePhotoSale(dto:StoreSaleDto,userId?:string,role?:string){ await this.members.assertCanManage(dto.eventId,userId,role); const ids=[...new Set(dto.imageIds)].map(id=>this.oid(id)); const result=await this.images.updateMany({_id:{$in:ids},eventId:this.oid(dto.eventId)},{$set:{isForSale:dto.isForSale}}); return {message:dto.isForSale?'Photos enabled for sale':'Photos removed from sale',updated:result.modifiedCount}; }
  async listOrders(query:StoreOrderQueryDto,userId?:string,role?:string){ await this.members.assertCanManage(query.eventId,userId,role); const filter:any={eventId:this.oid(query.eventId)}; if(query.status) filter.status=query.status; const data=await this.orders.find(filter).populate('imageIds','imageUrl').sort({createdAt:-1}).limit(query.limit||100).lean(); return {data,totalItems:data.length}; }
}
