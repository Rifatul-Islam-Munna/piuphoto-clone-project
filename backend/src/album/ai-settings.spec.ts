import 'reflect-metadata';
import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';
import { Types } from 'mongoose';
import { AI_PRESETS, IDENTITY_GUARD, PRESET_PROMPTS, canShowPhotoVersion, presetInstructions, publicationForUpload, resolveAiSettings } from './ai-settings';
import { UpdateAlbumDto } from './dto/album.dto';
import { UpdateEventDto } from '../event/dto/create-event.dto';
import { GalleryAccessService } from '../gallery-access/gallery-access.service';

describe('Album AI settings', () => {
  it('inherits defaults and honors an explicit false or empty album override', () => {
    const event = {autoEnhanceImages: true, aiPreset: 'sports' as const, aiPrompt: 'Event notes', aiGalleryMode: 'enhanced_only' as const};
    expect(resolveAiSettings(event, {autoEnhanceImages: false, aiPrompt: '', aiPreset: 'portrait', aiGalleryMode: 'both'})).toEqual({
      autoEnhanceImages: false, aiPreset: 'portrait', aiPrompt: '', aiGalleryMode: 'both',
    });
    expect(resolveAiSettings(event, {autoEnhanceImages: null, aiPreset: null, aiPrompt: null, aiGalleryMode: null})).toEqual(event);
    expect(resolveAiSettings({}).aiPreset).toBe('auto');
    expect(resolveAiSettings({}).aiGalleryMode).toBeUndefined();
  });

  it('has an effective prompt for every preset and retains the custom notes', () => {
    expect(new Set(AI_PRESETS.map(preset => PRESET_PROMPTS[preset])).size).toBe(AI_PRESETS.length);
    expect(presetInstructions({aiPreset: 'low_light', aiPrompt: 'Keep warm tones'}, 'Reduce noise')).toContain('Lift underexposed shadows');
    expect(presetInstructions({aiPreset: 'low_light', aiPrompt: 'Keep warm tones'}, 'Reduce noise')).toContain('Photographer notes: Keep warm tones');
    expect(IDENTITY_GUARD).toContain('Never replace faces');
  });

  it('retains legacy publication rules and never bypasses manual review', () => {
    expect(publicationForUpload('auto_upload', false, {})).toEqual({original: true, enhanced: false});
    expect(publicationForUpload('auto_ai', false, {})).toEqual({original: false, enhanced: true});
    for (const aiGalleryMode of ['both', 'enhanced_only'] as const) {
      expect(publicationForUpload('auto_upload', false, {aiGalleryMode})).toEqual({original: true, enhanced: true});
      expect(publicationForUpload('manual', false, {aiGalleryMode})).toEqual({original: false, enhanced: false});
      expect(publicationForUpload('auto_ai', true, {aiGalleryMode})).toEqual({original: false, enhanced: false});
    }
    expect(canShowPhotoVersion({isEnhanced: false}, 'enhanced_only')).toBe(false);
    expect(canShowPhotoVersion({isEnhanced: true}, 'enhanced_only')).toBe(true);
    expect(canShowPhotoVersion({mediaType: 'video'}, 'enhanced_only')).toBe(true);
  });

  it('validates presets, notes, display modes and inheritance for album and event updates', async () => {
    for (const dto of [UpdateAlbumDto, UpdateEventDto]) {
      expect(await validate(plainToInstance(dto, {aiPreset: 'portrait', aiPrompt: 'Warm tones', aiGalleryMode: 'both', autoEnhanceImages: false}))).toHaveLength(0);
      expect(await validate(plainToInstance(dto, {aiPreset: null, aiPrompt: null, aiGalleryMode: null, autoEnhanceImages: null}))).toHaveLength(0);
      expect(await validate(plainToInstance(dto, {aiPreset: 'bogus', aiGalleryMode: 'bogus', aiPrompt: 'x'.repeat(1001), autoEnhanceImages: 'yes'}))).toHaveLength(4);
    }
  });

  it('filters public originals according to scoped and inherited settings', async () => {
    const eventId = new Types.ObjectId();
    const albumId = new Types.ObjectId();
    const query = (value: unknown) => ({select: jest.fn().mockReturnValue({lean: jest.fn().mockResolvedValue(value)})});
    const events = {findById: jest.fn().mockReturnValue(query({aiGalleryMode: 'both'}))};
    const albums = {findOne: jest.fn().mockReturnValue(query({aiGalleryMode: 'enhanced_only'})), find: jest.fn().mockReturnValue(query([{_id: albumId}]))};
    const service = new GalleryAccessService(events as never, albums as never, {} as never, {} as never, {} as never, {} as never);
    expect(await service.publishedVersionFilter(String(eventId), String(albumId))).toEqual({$or: [{isEnhanced: true}, {mediaType: 'video'}]});
    expect(await service.publishedVersionFilter(String(eventId))).toEqual({$or: [{isEnhanced: true}, {mediaType: 'video'}, {albumId: {$nin: [albumId]}}]});
    events.findById.mockReturnValue(query({aiGalleryMode: 'enhanced_only'}));
    albums.findOne.mockReturnValue(query({aiGalleryMode: 'both'}));
    expect(await service.publishedVersionFilter(String(eventId), String(albumId))).toEqual({});
    expect(await service.publishedVersionFilter(String(eventId))).toEqual({$or: [{isEnhanced: true}, {mediaType: 'video'}, {albumId: {$in: [albumId]}}]});
  });
});
