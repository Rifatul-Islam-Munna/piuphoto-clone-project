import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { HydratedDocument, Types } from 'mongoose';

export enum UserType {
  ADMIN = 'admin',
  EDITOR = 'editor',
  USER = 'user',
  PHOTOGRAPHER = 'photographer',
}

export type UserDocument = HydratedDocument<User>;

@Schema({ timestamps: true, autoIndex: true, virtuals: true })
export class User {
  @Prop({ required: true, trim: true })
  name: string;

  @Prop({ trim: true, unique: true, sparse: true })
  userId?: string;

  @Prop({ default: true })
  isPublished: boolean;

  @Prop({ default: false })
  isActive: boolean;

  @Prop({ type: String, enum: UserType, default: UserType.USER })
  role: UserType;

  @Prop({ lowercase: true, trim: true })
  email?: string;

  @Prop({ trim: true, unique: true, sparse: true })
  phone?: string;

  @Prop({ trim: true })
  whatsapp?: string;

  @Prop({ required: true, select: false })
  password: string;

  @Prop({ default: true })
  isEmailVerified: boolean;

  @Prop({ trim: true })
  gender?: string;

  @Prop({ trim: true })
  maritalStatus?: string;

  @Prop({ min: 10, max: 100 })
  age?: number;

@Prop({ trim: true })
  bloodGroup?: string;

  @Prop({ min: 20, max: 200 })
  weight?: number;

  @Prop({ type: Types.ObjectId, ref: 'SubscriptionPlan', default: null })
  subscriptionPlanId?: Types.ObjectId;

  @Prop({ default: false })
  isSubscriber: boolean;

  @Prop({ default: 0, min: 0 })
  credits: number;

  @Prop()
  subscriptionStartDate?: Date;

  @Prop()
  subscriptionEndDate?: Date;

  @Prop({ type: Object })
  profileImage?: { url: string; key: string };
}

export const UserSchema = SchemaFactory.createForClass(User);

UserSchema.index(
  { phone: 1 },
  {
    name: 'phone_1',
    unique: true,
    partialFilterExpression: {
      phone: { $type: 'string' },
    },
  },
);

UserSchema.index(
  { email: 1 },
  {
    name: 'email_1',
    unique: true,
    partialFilterExpression: {
      email: { $type: 'string' },
    },
  },
);

UserSchema.index({
  name: 'text',
  email: 'text',
  userId: 'text',
  phone: 'text',
  whatsapp: 'text',
});
