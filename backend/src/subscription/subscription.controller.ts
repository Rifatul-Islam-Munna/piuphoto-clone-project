import {
  Controller,
  Get,
  Post,
  Body,
  Patch,
  Delete,
  Query,
  Req,
  UseGuards,
  Logger,
} from '@nestjs/common';
import { SubscriptionPlanService } from './subscription.service';
import {
  CreateSubscriptionPlanDto,
  CreateSubscriptionCheckoutDto,
  InvoiceQueryDto,
  PurchaseHistoryFilterDto,
  UpdateSubscriptionPlanDto,
  SubscriptionPlanFilterDto,
  FindOnePlanDto,
  VerifySubscriptionCheckoutDto,
} from './dto/create-subscription-plan.dto';
import { AuthGuard } from '../lib/auth.guard';
import type { ExpressRequest } from '../lib/auth.guard';
import { RolesGuard } from '../lib/roles.guard';
import { Roles } from '../lib/roles.decorator';
import { UserType } from '../user/entities/user.entity';

@Controller('subscription-plan')
export class SubscriptionPlanController {
  private logger = new Logger(SubscriptionPlanController.name);

  constructor(private readonly subscriptionPlanService: SubscriptionPlanService) {}

  @Post()
  @UseGuards(AuthGuard, RolesGuard)
  @Roles(UserType.ADMIN)
  create(@Body() createDto: CreateSubscriptionPlanDto) {
    return this.subscriptionPlanService.create(createDto);
  }

  @Get('get-all')
  async findAll(@Query() filter: SubscriptionPlanFilterDto) {
    return this.subscriptionPlanService.findAll(filter);
  }

  @Get('get-one')
  findOne(@Query() query: FindOnePlanDto) {
    return this.subscriptionPlanService.findOne(query);
  }

  @Post('create-checkout-session')
  @UseGuards(AuthGuard)
  createCheckoutSession(
    @Body() body: CreateSubscriptionCheckoutDto,
    @Req() req: ExpressRequest,
  ) {
    return this.subscriptionPlanService.createCheckoutSession(
      body.id,
      req.user?.id,
    );
  }

  @Get('verify-checkout')
  @UseGuards(AuthGuard)
  verifyCheckout(
    @Query() query: VerifySubscriptionCheckoutDto,
    @Req() req: ExpressRequest,
  ) {
    return this.subscriptionPlanService.verifyCheckout(
      query.sessionId,
      req.user?.id,
    );
  }

  @Get('purchase-history')
  @UseGuards(AuthGuard, RolesGuard)
  @Roles(UserType.ADMIN)
  getPurchaseHistory(@Query() query: PurchaseHistoryFilterDto) {
    return this.subscriptionPlanService.getPurchaseHistory(query.type);
  }

  @Get('invoice')
  @UseGuards(AuthGuard, RolesGuard)
  @Roles(UserType.ADMIN)
  getInvoice(@Query() query: InvoiceQueryDto) {
    return this.subscriptionPlanService.getInvoiceDetails(
      query.id,
      query.type as 'plan' | 'addon',
    );
  }

  @Patch('update')
  @UseGuards(AuthGuard, RolesGuard)
  @Roles(UserType.ADMIN)
  update(
    @Body() updateDto: UpdateSubscriptionPlanDto,
    @Query() query: FindOnePlanDto,
  ) {
    return this.subscriptionPlanService.update(updateDto, query.id);
  }

  @Delete('delete')
  @UseGuards(AuthGuard, RolesGuard)
  @Roles(UserType.ADMIN)
  remove(@Query() query: FindOnePlanDto) {
    return this.subscriptionPlanService.remove(query.id);
  }

  @Patch('toggle-active')
  @UseGuards(AuthGuard, RolesGuard)
  @Roles(UserType.ADMIN)
  toggleActive(@Query() query: FindOnePlanDto) {
    return this.subscriptionPlanService.toggleActive(query.id);
  }

  @Patch('toggle-popular')
  @UseGuards(AuthGuard, RolesGuard)
  @Roles(UserType.ADMIN)
  togglePopular(@Query() query: FindOnePlanDto) {
    return this.subscriptionPlanService.togglePopular(query.id);
  }
}
