import { Module } from '@nestjs/common';
import { MongooseModule } from '@nestjs/mongoose';
import { EventMemberModule } from '../event-member/event-member.module';
import { UploadSessionModule } from '../upload-session/upload-session.module';
import { PhotoTransferStatus, PhotoTransferStatusSchema } from './entities/photo-transfer-status.entity';
import { TransferStatusController } from './transfer-status.controller';
import { TransferStatusService } from './transfer-status.service';

@Module({
  imports: [
    EventMemberModule,
    UploadSessionModule,
    MongooseModule.forFeature([
      { name: PhotoTransferStatus.name, schema: PhotoTransferStatusSchema },
    ]),
  ],
  controllers: [TransferStatusController],
  providers: [TransferStatusService],
  exports: [TransferStatusService],
})
export class TransferStatusModule {}
