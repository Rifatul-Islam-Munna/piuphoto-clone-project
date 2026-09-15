import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { HydratedDocument, Types } from 'mongoose';

export enum EventMemberRole {
  OWNER = 'owner',
  EVENT_PLANNER = 'event_planner',
  PHOTOGRAPHER = 'photographer',
  ASSISTANT_PHOTOGRAPHER = 'assistant_photographer',
  RETOUCHER = 'retoucher',
  REVIEWER = 'reviewer',
}

export enum EventMemberStatus {
  PENDING = 'pending',
  ACTIVE = 'active',
  DECLINED = 'declined',
}

export type EventMemberDocument = HydratedDocument<EventMember>;

@Schema({ timestamps: true, autoIndex: true, virtuals: true })
export class EventMember {
  @Prop({ type: Types.ObjectId, ref: 'Event', required: true, index: true })
  eventId: Types.ObjectId;

  @Prop({ type: Types.ObjectId, ref: 'User', required: true, index: true })
  userId: Types.ObjectId;

  @Prop({ type: Types.ObjectId, ref: 'User', required: true, index: true })
  invitedBy: Types.ObjectId;

  @Prop({
    type: String,
    enum: EventMemberRole,
    required: true,
    index: true,
  })
  role: EventMemberRole;

  @Prop({
    type: String,
    enum: EventMemberStatus,
    default: EventMemberStatus.PENDING,
    index: true,
  })
  status: EventMemberStatus;

  @Prop({ type: [Types.ObjectId], ref: 'Album', default: [] })
  assignedAlbumIds: Types.ObjectId[];

  @Prop({ default: false })
  canPublish: boolean;

  @Prop()
  respondedAt?: Date;
}

export const EventMemberSchema = SchemaFactory.createForClass(EventMember);

EventMemberSchema.index(
  { eventId: 1, userId: 1, role: 1 },
  { unique: true, name: 'event_member_role_unique' },
);
EventMemberSchema.index({ eventId: 1, status: 1, role: 1 });
EventMemberSchema.index({ userId: 1, status: 1, createdAt: -1 });
