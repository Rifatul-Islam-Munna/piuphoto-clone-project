import { Module } from '@nestjs/common';
import { UserService } from './user.service';
import { UserController } from './user.controller';
import { MongooseModule } from '@nestjs/mongoose';
import { User, UserSchema } from './entities/user.entity';
import {
  SubscriptionPlan,
  SubscriptionPlanSchema,
} from '../subscription/entities/subscription-plan.entity';
import { EventMemberModule } from '../event-member/event-member.module';

@Module({
  imports: [
    EventMemberModule,
    MongooseModule.forFeature([
      { name: User.name, schema: UserSchema },
      { name: SubscriptionPlan.name, schema: SubscriptionPlanSchema },
    ]),
  ],
  controllers: [UserController],
  providers: [UserService],
  exports: [UserService],
})
export class UserModule {}
