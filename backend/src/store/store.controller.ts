import {
  Body,
  Controller,
  Get,
  Headers,
  Patch,
  Post,
  Query,
  Req,
  Res,
  UseGuards,
} from '@nestjs/common';
import type { RawBodyRequest } from '@nestjs/common';
import { Throttle, ThrottlerGuard } from '@nestjs/throttler';
import type { Request, Response } from 'express';
import { AuthGuard } from '../lib/auth.guard';
import type { ExpressRequest } from '../lib/auth.guard';
import {
  StoreAccountSettingsDto,
  StoreCheckoutDto,
  StoreOrderQueryDto,
  StoreSaleDto,
  StoreSettingsDto,
  StoreVerifyDto,
} from './dto/store.dto';
import { StoreService } from './store.service';

@Controller('store')
export class StoreController {
  constructor(private readonly service: StoreService) {}
  @Get('public/catalog') catalog(
    @Query('eventId') eventId: string,
    @Query('albumId') albumId?: string,
  ) {
    return this.service.publicCatalog(eventId, albumId);
  }
  @Get('public/preview') async preview(
    @Query('eventId') eventId: string,
    @Query('imageId') imageId: string,
    @Res() res: Response,
  ) {
    const data = await this.service.preview(eventId, imageId);
    res.setHeader('Content-Type', 'image/jpeg');
    res.setHeader('Cache-Control', 'public,max-age=120');
    res.send(data);
  }
  @Post('public/checkout')
  @UseGuards(ThrottlerGuard)
  @Throttle({ default: { limit: 20, ttl: 3600000 } })
  checkout(@Body() body: StoreCheckoutDto) {
    return this.service.checkout(body);
  }
  @Post('public/verify')
  @UseGuards(ThrottlerGuard)
  @Throttle({ default: { limit: 30, ttl: 3600000 } })
  verify(@Body() body: StoreVerifyDto) {
    return this.service.verifyCheckout(body);
  }
  @Get('public/order') order(
    @Query('orderId') orderId: string,
    @Query('token') token: string,
  ) {
    return this.service.orderByToken(orderId, token);
  }
  @Get('public/download')
  async download(
    @Query('orderId') orderId: string,
    @Query('token') token: string,
    @Query('imageId') imageId: string,
    @Res() res: Response,
  ) {
    const file = await this.service.downloadPurchased(orderId, token, imageId);
    res.setHeader('Content-Type', file.contentType);
    res.setHeader(
      'Content-Disposition',
      `attachment; filename="${file.filename}"`,
    );
    res.setHeader('Cache-Control', 'private,no-store');
    res.send(file.buffer);
  }
  @Post('stripe-webhook') webhook(
    @Query('eventId') eventId: string | undefined,
    @Req() req: RawBodyRequest<Request>,
    @Headers('stripe-signature') signature: string,
    @Body() body: any,
  ) {
    return this.service.webhook(eventId, req.rawBody, signature, body);
  }
  @Get('account-settings') @UseGuards(AuthGuard)
  accountSettings(@Req() req: ExpressRequest) {
    return this.service.accountSettings(req.user?.id);
  }
  @Patch('account-settings') @UseGuards(AuthGuard)
  updateAccountSettings(
    @Body() body: StoreAccountSettingsDto,
    @Req() req: ExpressRequest,
  ) {
    return this.service.updateAccountSettings(body, req.user?.id);
  }
  @Get('settings') @UseGuards(AuthGuard) settings(
    @Query('eventId') eventId: string,
    @Req() req: ExpressRequest,
  ) {
    return this.service.settingsForPlanner(
      eventId,
      req.user?.id,
      req.user?.role,
    );
  }
  @Patch('settings') @UseGuards(AuthGuard) update(
    @Body() body: StoreSettingsDto,
    @Req() req: ExpressRequest,
  ) {
    return this.service.updateSettings(body, req.user?.id, req.user?.role);
  }
  @Get('sale-photos') @UseGuards(AuthGuard) salePhotos(
    @Query('eventId') eventId: string,
    @Req() req: ExpressRequest,
  ) {
    return this.service.salePhotosForPlanner(
      eventId,
      req.user?.id,
      req.user?.role,
    );
  }
  @Patch('sale-photos') @UseGuards(AuthGuard) updateSale(
    @Body() body: StoreSaleDto,
    @Req() req: ExpressRequest,
  ) {
    return this.service.updatePhotoSale(body, req.user?.id, req.user?.role);
  }
  @Get('orders') @UseGuards(AuthGuard) orders(
    @Query() query: StoreOrderQueryDto,
    @Req() req: ExpressRequest,
  ) {
    return this.service.listOrders(query, req.user?.id, req.user?.role);
  }
}
