import { Module } from '@nestjs/common';
import { MongooseModule } from '@nestjs/mongoose';
import { ConfigModule } from '@nestjs/config';
import { AddonController } from './addon.controller';
import { AddonService } from './addon.service';
import { Addon, AddonSchema } from './entities/addon.entity';
import {
  AddonPurchase,
  AddonPurchaseSchema,
} from './entities/addon-purchase.entity';
import { User, UserSchema } from '../user/entities/user.entity';

@Module({
  imports: [
    ConfigModule,
    MongooseModule.forFeature([
      { name: Addon.name, schema: AddonSchema },
      { name: AddonPurchase.name, schema: AddonPurchaseSchema },
      { name: User.name, schema: UserSchema },
    ]),
  ],
  controllers: [AddonController],
  providers: [AddonService],
  exports: [AddonService],
})
export class AddonModule {}

