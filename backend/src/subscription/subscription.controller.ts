import {
  Controller,
  Get,
  Post,
  Body,
  Patch,
  Delete,
  Query,
  UseGuards,
  Logger,
} from '@nestjs/common';
import { SubscriptionPlanService } from './subscription.service';
import {
  CreateSubscriptionPlanDto,
  UpdateSubscriptionPlanDto,
  SubscriptionPlanFilterDto,
  FindOnePlanDto,
} from './dto/create-subscription-plan.dto';
import { AuthGuard } from '../lib/auth.guard';
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