import {
  Body,
  Controller,
  Delete,
  Get,
  Patch,
  Post,
  Query,
  Req,
  UseGuards,
} from '@nestjs/common';
import { AddonService } from './addon.service';
import {
  AddonFilterDto,
  CreateAddonCheckoutDto,
  CreateAddonDto,
  FindOneAddonDto,
  UpdateAddonDto,
  VerifyAddonCheckoutDto,
} from './dto/create-addon.dto';
import { AuthGuard } from '../lib/auth.guard';
import type { ExpressRequest } from '../lib/auth.guard';
import { RolesGuard } from '../lib/roles.guard';
import { Roles } from '../lib/roles.decorator';
import { UserType } from '../user/entities/user.entity';

@Controller('addon')
export class AddonController {
  constructor(private readonly addonService: AddonService) {}

  @Post()
  @UseGuards(AuthGuard, RolesGuard)
  @Roles(UserType.ADMIN)
  create(@Body() createDto: CreateAddonDto) {
    return this.addonService.create(createDto);
  }

  @Get('get-all')
  findAll(@Query() filter: AddonFilterDto) {
    return this.addonService.findAll(filter);
  }

  @Get('get-one')
  findOne(@Query() query: FindOneAddonDto) {
    return this.addonService.findOne(query.id);
  }

  @Patch('update')
  @UseGuards(AuthGuard, RolesGuard)
  @Roles(UserType.ADMIN)
  update(
    @Body() updateDto: UpdateAddonDto,
    @Query() query: FindOneAddonDto,
  ) {
    return this.addonService.update(query.id, updateDto);
  }

  @Delete('delete')
  @UseGuards(AuthGuard, RolesGuard)
  @Roles(UserType.ADMIN)
  remove(@Query() query: FindOneAddonDto) {
    return this.addonService.remove(query.id);
  }

  @Patch('toggle-active')
  @UseGuards(AuthGuard, RolesGuard)
  @Roles(UserType.ADMIN)
  toggleActive(@Query() query: FindOneAddonDto) {
    return this.addonService.toggleActive(query.id);
  }

  @Post('create-checkout-session')
  @UseGuards(AuthGuard)
  createCheckoutSession(
    @Body() createCheckoutDto: CreateAddonCheckoutDto,
    @Req() req: ExpressRequest,
  ) {
    return this.addonService.createCheckoutSession(
      createCheckoutDto,
      req.user?.id,
    );
  }

  @Post('mobile-payment-sheet')
  @UseGuards(AuthGuard)
  createMobilePaymentSheet(
    @Body() createCheckoutDto: CreateAddonCheckoutDto,
    @Req() req: ExpressRequest,
  ) {
    return this.addonService.createMobilePaymentSheet(
      createCheckoutDto,
      req.user?.id,
    );
  }

  @Get('verify-checkout')
  @UseGuards(AuthGuard)
  verifyCheckout(
    @Query() verifyDto: VerifyAddonCheckoutDto,
    @Req() req: ExpressRequest,
  ) {
    return this.addonService.verifyCheckout(verifyDto, req.user?.id);
  }

  @Get('verify-mobile-payment')
  @UseGuards(AuthGuard)
  verifyMobilePayment(
    @Query('paymentIntentId') paymentIntentId: string,
    @Req() req: ExpressRequest,
  ) {
    return this.addonService.verifyMobilePayment(paymentIntentId, req.user?.id);
  }
}
