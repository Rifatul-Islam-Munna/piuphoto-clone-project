import { Module } from '@nestjs/common';
import { MongooseModule } from '@nestjs/mongoose';
import { ApiWebhookEndpoint, ApiWebhookEndpointSchema } from './entities/api-webhook-endpoint.entity';
import { ApiWebhookDelivery, ApiWebhookDeliverySchema } from './entities/api-webhook-delivery.entity';
import { WorkflowWebhookPublisherService } from './workflow-webhook-publisher.service';
@Module({imports:[MongooseModule.forFeature([{name:ApiWebhookEndpoint.name,schema:ApiWebhookEndpointSchema},{name:ApiWebhookDelivery.name,schema:ApiWebhookDeliverySchema}])],providers:[WorkflowWebhookPublisherService],exports:[WorkflowWebhookPublisherService]})
export class WorkflowWebhookPublisherModule {}
