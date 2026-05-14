import { Injectable } from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { Model } from 'mongoose';
import { CreateSettingDto } from './dto/create-setting.dto';
import { UpdateSettingDto } from './dto/update-setting.dto';
import { Setting, SettingDocument } from './entities/setting.entity';
import { defaultWebsiteSettings } from './settings.defaults';

@Injectable()
export class SettingsService {
  constructor(
    @InjectModel(Setting.name)
    private settingModel: Model<SettingDocument>,
  ) {}

  private isPlainObject(value: unknown): value is Record<string, unknown> {
    return !!value && typeof value === 'object' && !Array.isArray(value);
  }

  private mergeDeep(
    current: Record<string, unknown>,
    updates: Record<string, unknown>,
  ): Record<string, unknown> {
    const merged: Record<string, unknown> = { ...current };

    Object.entries(updates).forEach(([key, value]) => {
      if (value === undefined) {
        return;
      }

      if (Array.isArray(value)) {
        merged[key] = value;
        return;
      }

      if (this.isPlainObject(value) && this.isPlainObject(merged[key])) {
        merged[key] = this.mergeDeep(
          merged[key] as Record<string, unknown>,
          value,
        );
        return;
      }

      merged[key] = value;
    });

    return merged;
  }

  private sanitizeSettingsPayload(payload: Record<string, unknown>) {
    const next = { ...payload };
    delete next._id;
    delete next.__v;
    delete next.createdAt;
    delete next.updatedAt;
    return next;
  }

  private async ensureWebsiteSettings() {
    const existing = await this.settingModel
      .find({ key: 'website' })
      .sort({ updatedAt: -1, createdAt: -1, _id: -1 })
      .lean();

    if (existing.length > 0) {
      const [primary, ...duplicates] = existing;

      if (duplicates.length > 0) {
        await this.settingModel.deleteMany({
          _id: { $in: duplicates.map((item) => item._id) },
        });
      }

      return primary;
    }

    const created = await this.settingModel.create(defaultWebsiteSettings);
    return created.toObject();
  }

  create(createSettingDto: CreateSettingDto) {
    return this.updateWebsiteSettings(createSettingDto);
  }

  async getPublicSettings() {
    const settings = await this.ensureWebsiteSettings();
    return { data: settings };
  }

  async getAdminSettings() {
    const settings = await this.ensureWebsiteSettings();
    return { data: settings };
  }

  async findAll() {
    return this.getPublicSettings();
  }

  async findOne() {
    return this.getAdminSettings();
  }

  async updateWebsiteSettings(updateSettingDto: UpdateSettingDto) {
    const current = await this.ensureWebsiteSettings();
    const merged = this.sanitizeSettingsPayload(this.mergeDeep(
      current as unknown as Record<string, unknown>,
      updateSettingDto as unknown as Record<string, unknown>,
    ));

    const updated = await this.settingModel
      .findOneAndUpdate(
        { _id: current._id },
        { $set: { ...merged, key: 'website' } },
        { new: true, upsert: true, setDefaultsOnInsert: true },
      )
      .lean();

    return {
      message: 'Settings updated successfully',
      data: updated,
    };
  }

  update(_id: number, updateSettingDto: UpdateSettingDto) {
    return this.updateWebsiteSettings(updateSettingDto);
  }

  remove(_id: number) {
    return {
      message: 'Settings are singleton and cannot be removed',
    };
  }
}
