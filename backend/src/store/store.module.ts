import { Module } from '@nestjs/common';
import { MongooseModule } from '@nestjs/mongoose';
import { EventMemberModule } from '../event-member/event-member.module';
import { NotificationModule } from '../notification/notification.module';
import { Event, EventSchema } from '../event/entities/event.entity';
import { EventImage, EventImageSchema } from '../event-image/entities/event-image.entity';
import { StoreOrder, StoreOrderSchema } from './entities/store-order.entity';
import { StoreSettings, StoreSettingsSchema } from './entities/store-settings.entity';
import { StoreController } from './store.controller';
import { StoreService } from './store.service';
@Module({imports:[EventMemberModule,NotificationModule,MongooseModule.forFeature([{name:StoreOrder.name,schema:StoreOrderSchema},{name:StoreSettings.name,schema:StoreSettingsSchema},{name:Event.name,schema:EventSchema},{name:EventImage.name,schema:EventImageSchema}])],controllers:[StoreController],providers:[StoreService],exports:[StoreService]})
export class StoreModule {}
