import { Body, Controller, Delete, Get, Headers, Param, Patch, Post, Query, Req, UseGuards } from '@nestjs/common';
import { AuthGuard } from '../lib/auth.guard';
import type { ExpressRequest } from '../lib/auth.guard';
import { CreateApiKeyDto, CreateApiWebhookDto, DeleteApiWebhookDto, RevokeApiKeyDto } from './dto/external-api.dto';
import { ExternalApiService } from './external-api.service';
@Controller('api-platform')
@UseGuards(AuthGuard)
export class ApiPlatformController {
  constructor(private readonly api:ExternalApiService){}
  @Post('keys') createKey(@Body() body:CreateApiKeyDto,@Req() req:ExpressRequest){ return this.api.createKey(body,req.user?.id,req.user?.role); }
  @Get('keys') keys(@Req() req:ExpressRequest){ return this.api.listKeys(req.user?.id); }
  @Get('audit') audit(@Req() req:ExpressRequest){ return this.api.listAudit(req.user?.id); }
  @Post('keys/revoke') revoke(@Body() body:RevokeApiKeyDto,@Req() req:ExpressRequest){ return this.api.revokeKey(body.id,req.user?.id); }
  @Post('webhooks') createWebhook(@Body() body:CreateApiWebhookDto,@Req() req:ExpressRequest){ return this.api.createWebhook(body,req.user?.id,req.user?.role); }
  @Get('webhooks') webhooks(@Query('eventId') eventId:string,@Req() req:ExpressRequest){ return this.api.listWebhooks(eventId,req.user?.id,req.user?.role); }
  @Delete('webhooks') removeWebhook(@Query() body:DeleteApiWebhookDto,@Req() req:ExpressRequest){ return this.api.removeWebhook(body.id,req.user?.id,req.user?.role); }
  @Get('webhook-deliveries') deliveries(@Query('eventId') eventId:string,@Req() req:ExpressRequest){ return this.api.listWebhookDeliveries(eventId,req.user?.id,req.user?.role); }
  @Post('webhook-deliveries/retry') retryDelivery(@Body() body:DeleteApiWebhookDto,@Req() req:ExpressRequest){ return this.api.retryWebhookDelivery(body.id,req.user?.id,req.user?.role); }
}
