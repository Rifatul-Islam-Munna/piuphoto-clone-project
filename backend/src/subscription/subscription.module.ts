import { Module } from '@nestjs/common';
import { MongooseModule } from '@nestjs/mongoose';
import { SubscriptionPlanService } from './subscription.service';
import { SubscriptionPlanController } from './subscription.controller';
import {
  SubscriptionPlan,
  SubscriptionPlanSchema,
} from './entities/subscription-plan.entity';
import {
  SubscriptionPlanPurchase,
  SubscriptionPlanPurchaseSchema,
} from './entities/subscription-plan-purchase.entity';
import { UserModule } from '../user/user.module';
import { Addon, AddonSchema } from '../addon/entities/addon.entity';
import {
  AddonPurchase,
  AddonPurchaseSchema,
} from '../addon/entities/addon-purchase.entity';
import { User, UserSchema } from '../user/entities/user.entity';

@Module({
  imports: [
    UserModule,
    MongooseModule.forFeature([
      { name: SubscriptionPlan.name, schema: SubscriptionPlanSchema },
      {
        name: SubscriptionPlanPurchase.name,
        schema: SubscriptionPlanPurchaseSchema,
      },
      { name: Addon.name, schema: AddonSchema },
      { name: AddonPurchase.name, schema: AddonPurchaseSchema },
      { name: User.name, schema: UserSchema },
    ]),
  ],
  controllers: [SubscriptionPlanController],
  providers: [SubscriptionPlanService],
  exports: [SubscriptionPlanService],
})
export class SubscriptionModule {}
