import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { HydratedDocument, Types } from 'mongoose';

export enum EventInvitationStatus {
  PENDING = 'pending',
  ACCEPTED = 'accepted',
}

export type EventInvitationDocument = HydratedDocument<EventInvitation>;

@Schema({ timestamps: true, autoIndex: true, virtuals: true })
export class EventInvitation {
  @Prop({ type: Types.ObjectId, ref: 'Event', required: true, index: true })
  eventId: Types.ObjectId;

  @Prop({ type: Types.ObjectId, ref: 'User', required: true, index: true })
  userId: Types.ObjectId;

  @Prop({ type: Types.ObjectId, ref: 'User', required: true, index: true })
  photographerId: Types.ObjectId;

  @Prop({
    type: String,
    enum: EventInvitationStatus,
    default: EventInvitationStatus.PENDING,
    index: true,
  })
  status: EventInvitationStatus;

  @Prop()
  respondedAt?: Date;
}

export const EventInvitationSchema =
  SchemaFactory.createForClass(EventInvitation);

EventInvitationSchema.index(
  { eventId: 1, photographerId: 1 },
  { unique: true, name: 'event_photographer_unique_invite' },
);

