import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { HydratedDocument } from 'mongoose';
import { defaultWebsiteSettings } from '../settings.defaults';

export type SettingDocument = HydratedDocument<Setting>;

@Schema({ timestamps: true, autoIndex: true })
export class Setting {
  @Prop({ required: true, unique: true, default: 'website' })
  key: string;

  @Prop({ type: Object, default: () => defaultWebsiteSettings.site })
  site: Record<string, unknown>;

  @Prop({ type: Object, default: () => defaultWebsiteSettings.navbar })
  navbar: Record<string, unknown>;

  @Prop({ type: Object, default: () => defaultWebsiteSettings.hero })
  hero: Record<string, unknown>;

  @Prop({ type: Object, default: () => defaultWebsiteSettings.productShowcase })
  productShowcase: Record<string, unknown>;

  @Prop({ type: Object, default: () => defaultWebsiteSettings.featuresGrid })
  featuresGrid: Record<string, unknown>;

  @Prop({ type: Object, default: () => defaultWebsiteSettings.flyPhotos })
  flyPhotos: Record<string, unknown>;

  @Prop({ type: Object, default: () => defaultWebsiteSettings.eventStreaming })
  eventStreaming: Record<string, unknown>;

  @Prop({ type: Object, default: () => defaultWebsiteSettings.apiSection })
  apiSection: Record<string, unknown>;

  @Prop({ type: Object, default: () => defaultWebsiteSettings.connectionSection })
  connectionSection: Record<string, unknown>;

  @Prop({ type: Object, default: () => defaultWebsiteSettings.trustedBrands })
  trustedBrands: Record<string, unknown>;

  @Prop({ type: Object, default: () => defaultWebsiteSettings.caseStudy })
  caseStudy: Record<string, unknown>;

  @Prop({ type: Object, default: () => defaultWebsiteSettings.newsroom })
  newsroom: Record<string, unknown>;

  @Prop({ type: Object, default: () => defaultWebsiteSettings.finalCta })
  finalCta: Record<string, unknown>;

  @Prop({ type: Object, default: () => defaultWebsiteSettings.footer })
  footer: Record<string, unknown>;

  @Prop({ type: Object, default: () => defaultWebsiteSettings.policy })
  policy: Record<string, unknown>;
}

export const SettingSchema = SchemaFactory.createForClass(Setting);
