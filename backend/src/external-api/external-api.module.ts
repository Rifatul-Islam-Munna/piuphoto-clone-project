import { Module } from '@nestjs/common';
import { AlbumModule } from '../album/album.module';
import { GalleryAccessModule } from '../gallery-access/gallery-access.module';
import { GuestGalleryModule } from '../guest-gallery/guest-gallery.module';
import { ImageModule } from '../image/image.module';
import { MongooseModule } from '@nestjs/mongoose';
import { AnalyticsModule } from '../analytics/analytics.module';
import { EventImageModule } from '../event-image/event-image.module';
import { EventMemberModule } from '../event-member/event-member.module';
import { EventModule } from '../event/event.module';
import { Event, EventSchema } from '../event/entities/event.entity';
import { EventImage, EventImageSchema } from '../event-image/entities/event-image.entity';
import { ApiPlatformController } from './api-platform.controller';
import { ExternalV1Controller } from './external-v1.controller';
import { ExternalApiService } from './external-api.service';
import { ApiCredential, ApiCredentialSchema } from './entities/api-credential.entity';
import { ApiWebhookEndpoint, ApiWebhookEndpointSchema } from './entities/api-webhook-endpoint.entity';
import { ApiWebhookDelivery, ApiWebhookDeliverySchema } from './entities/api-webhook-delivery.entity';
import { ApiUsageBucket, ApiUsageBucketSchema } from './entities/api-usage-bucket.entity';
import { ApiAuditLog, ApiAuditLogSchema } from './entities/api-audit-log.entity';
@Module({imports:[EventMemberModule,EventModule,EventImageModule,AnalyticsModule,AlbumModule,GalleryAccessModule,GuestGalleryModule,ImageModule,MongooseModule.forFeature([
  {name:ApiCredential.name,schema:ApiCredentialSchema},{name:ApiWebhookEndpoint.name,schema:ApiWebhookEndpointSchema},{name:ApiWebhookDelivery.name,schema:ApiWebhookDeliverySchema},{name:ApiUsageBucket.name,schema:ApiUsageBucketSchema},{name:ApiAuditLog.name,schema:ApiAuditLogSchema},{name:Event.name,schema:EventSchema},{name:EventImage.name,schema:EventImageSchema}
])],controllers:[ApiPlatformController,ExternalV1Controller],providers:[ExternalApiService],exports:[ExternalApiService]})
export class ExternalApiModule {}
