import { ApiProperty } from '@nestjs/swagger';
import { IsMongoId, IsNotEmpty } from 'class-validator';

export class InvitePhotographerDto {
  @ApiProperty({ example: '507f1f77bcf86cd799439011' })
  @IsMongoId()
  @IsNotEmpty()
  eventId: string;

  @ApiProperty({ example: '507f1f77bcf86cd799439012' })
  @IsMongoId()
  @IsNotEmpty()
  photographerId: string;
}

export class EventInvitationQueryDto {
  @ApiProperty({ example: '507f1f77bcf86cd799439013' })
  @IsMongoId()
  @IsNotEmpty()
  id: string;
}

