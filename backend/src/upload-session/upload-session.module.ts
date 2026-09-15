import { Module } from '@nestjs/common';
import { MongooseModule } from '@nestjs/mongoose';
import { EventMemberModule } from '../event-member/event-member.module';
import {
  UploadSession,
  UploadSessionSchema,
} from './entities/upload-session.entity';
import { UploadSessionController } from './upload-session.controller';
import { UploadSessionService } from './upload-session.service';

@Module({
  imports: [
    EventMemberModule,
    MongooseModule.forFeature([
      { name: UploadSession.name, schema: UploadSessionSchema },
    ]),
  ],
  controllers: [UploadSessionController],
  providers: [UploadSessionService],
  exports: [UploadSessionService],
})
export class UploadSessionModule {}
