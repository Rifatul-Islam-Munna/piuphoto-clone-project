import 'reflect-metadata';
import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';
import { resolveRetouchAdjustments, retouchInstructions } from './retouch-adjustments';
import { IDENTITY_GUARD, presetInstructions, resolveAiSettings } from './ai-settings';
import { UpdateAlbumDto } from './dto/album.dto';
import { UpdateEventDto } from '../event/dto/create-event.dto';

describe('Retouch adjustment profiles', () => {
  it('uses the selected scene defaults, independent portrait profiles and valid zero values', () => {
    const result = resolveRetouchAdjustments('low_light', {
      photo: { exposure: 0, noise: 87 },
      male: { blemish: 35 },
      female: { forehead: 0 },
    });
    expect(result.photo).toMatchObject({ exposure: 0, shadows: 95, noise: 87 });
    expect(result.male.blemish).toBe(35);
    expect(result.female.blemish).toBe(20);
    expect(result.female.forehead).toBe(0);
    expect(result.child.blemish).toBe(0);
  });

  it('clamps legacy or malformed stored values and does not allow unrestricted facial edits', () => {
    const result = resolveRetouchAdjustments('auto', {
      photo: { highlights: 900, deblur: -8 },
      male: { texture: 100, forehead: 90 },
      child: { blemish: 100 },
    });
    expect(result.photo.highlights).toBe(100);
    expect(result.photo.deblur).toBe(0);
    expect(result.male.texture).toBe(20);
    expect(result.male.forehead).toBe(25);
    expect(result.child.blemish).toBe(15);
  });

  it('passes actual settings to the model as adaptive priorities and explicit off instructions', () => {
    const instructions = presetInstructions({
      aiPreset: 'sports',
      aiPrompt: 'Keep natural skin',
      aiAdjustments: { photo: { deblur: 0, noise: 90 }, female: { blemish: 31 } },
    });
    expect(instructions).toContain('Photographer notes: Keep natural skin');
    expect(instructions).toContain('mild camera shake or motion blur only where detail is recoverable: OFF');
    expect(instructions).toContain('reduce luminance and chroma noise without waxy textures: up to 90%');
    expect(instructions).toContain('soften only temporary blemishes, preserving permanent marks: up to 31%');
    expect(instructions).toContain('No wrinkle, skin smoothing, under-eye, beauty or shape edits for children');
    expect(IDENTITY_GUARD).toContain('never reconstruct or redraw');
  });

  it('inherits event profiles unless the album chooses its own preset or profile', () => {
    const event = { aiPreset: 'low_light' as const, aiAdjustments: { photo: { noise: 77 } } };
    expect(resolveAiSettings(event, { aiAdjustments: null }).aiAdjustments).toEqual(event.aiAdjustments);
    expect(resolveAiSettings(event, { aiPreset: 'sports' }).aiAdjustments).toBeUndefined();
    expect(resolveAiSettings(event, { aiAdjustments: { photo: { noise: 0 } } }).aiAdjustments).toEqual({ photo: { noise: 0 } });
  });

  it('validates nested album and event controls including portrait caps and unknown fields', async () => {
    for (const dto of [UpdateAlbumDto, UpdateEventDto]) {
      const opts = { whitelist: true, forbidNonWhitelisted: true };
      expect(await validate(plainToInstance(dto, { aiAdjustments: { photo: { exposure: 95 }, female: { blemish: 32 }, child: { blemish: 0 } } }), opts)).toHaveLength(0);
      expect(await validate(plainToInstance(dto, { aiAdjustments: null }), opts)).toHaveLength(0);
      expect((await validate(plainToInstance(dto, { aiAdjustments: { photo: { exposure: 101 }, male: { forehead: 26 }, child: { blemish: 16, faceShape: 20 } } }), opts)).length).toBeGreaterThan(0);
      expect((await validate(plainToInstance(dto, { aiAdjustments: { child: { forehead: 1 } } }), opts)).length).toBeGreaterThan(0);
    }
  });
});
