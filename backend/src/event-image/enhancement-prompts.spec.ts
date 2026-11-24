import { IDENTITY_GUARD, identityGuard } from '../album/ai-settings';
import { buildEnhancementPrompt } from './enhancement-prompts';

describe('Professional enhancement requests', () => {
  it('preserves photographer notes and per-photo notes after a selected task', () => {
    const prompt = buildEnhancementPrompt({
      aiPreset: 'low_light',
      aiPrompt: 'Keep the blue stage lighting',
      aiAdjustments: { photo: { deblur: 0 }, female: { blemish: 100 } },
    }, 'SKIN BEAUTIFICATION: Keep freckles and existing makeup');

    expect(prompt).toContain('SELECTED TASK:');
    expect(prompt).toContain('Photographer notes: Keep the blue stage lighting');
    expect(prompt).toContain('Additional request: Keep freckles and existing makeup');
    expect(prompt).toContain('Lift underexposed shadows');
    expect(prompt).toContain('reduce mild camera shake or motion blur only where detail is recoverable: OFF');
    expect(prompt).toContain('soften only temporary blemishes, preserving permanent marks: up to 40%');
    expect(prompt.endsWith(IDENTITY_GUARD)).toBe(true);
    expect(prompt.split('NON-NEGOTIABLE:')).toHaveLength(2);
  });

  it.each([
    'No skin beautification; keep all skin untouched',
    'Do not use vehicle privacy protection',
    'Keep facial beautification disabled',
    'The sign says color enhancement',
  ])('does not turn a phrase inside custom notes into a selected task: %s', notes => {
    const prompt = buildEnhancementPrompt({}, notes);
    expect(prompt).not.toContain('SELECTED TASK:');
    expect(prompt).toContain('Additional request: ' + notes);
    expect(prompt.endsWith(IDENTITY_GUARD)).toBe(true);
  });

  it('supports both color spellings and notes on the next line', () => {
    expect(buildEnhancementPrompt({}, 'Colour enhancement')).toBe(buildEnhancementPrompt({}, 'Color enhancement'));
    const prompt = buildEnhancementPrompt({}, 'Facial beautification\nKeep the expression unchanged');
    expect(prompt).toContain('SELECTED TASK:');
    expect(prompt).toContain('Additional request: Keep the expression unchanged');
  });

  it('allows the plate text exception only for an explicitly selected privacy task', () => {
    const prompt = buildEnhancementPrompt({}, 'Vehicle privacy protection: Keep the car badge');
    expect(prompt).toContain('EXPLICIT VEHICLE PRIVACY TASK:');
    expect(prompt).toContain('Additional request: Keep the car badge');
    expect(prompt.endsWith(identityGuard(true))).toBe(true);
    expect(prompt).not.toContain('Never alter text, logos, signage, identifiers or license-plate characters.');
    expect(buildEnhancementPrompt({}, 'Blur the background').endsWith(IDENTITY_GUARD)).toBe(true);
  });

  it('uses an owner-selected task and lets an explicit per-photo task override it', () => {
    const settings = { aiPrompt: 'Vehicle privacy protection: Keep reflections' };
    const inherited = buildEnhancementPrompt(settings);
    expect(inherited).toContain('EXPLICIT VEHICLE PRIVACY TASK:');
    expect(inherited).toContain('Photographer notes: Keep reflections');
    expect(inherited.endsWith(identityGuard(true))).toBe(true);

    const overridden = buildEnhancementPrompt(settings, 'Color enhancement');
    expect(overridden).not.toContain('EXPLICIT VEHICLE PRIVACY TASK:');
    expect(overridden.endsWith(IDENTITY_GUARD)).toBe(true);
  });

  it('bounds both note sources without truncating the master prompt or final guard', () => {
    const prompt = buildEnhancementPrompt({ aiPrompt: 'a'.repeat(1500) }, 'b'.repeat(1500));
    expect(prompt).toContain('Photographer notes: ' + 'a'.repeat(1000));
    expect(prompt).not.toContain('a'.repeat(1001));
    expect(prompt).toContain('Additional request: ' + 'b'.repeat(1000));
    expect(prompt).not.toContain('b'.repeat(1001));
    expect(prompt.startsWith('TASK:')).toBe(true);
    expect(prompt.endsWith(IDENTITY_GUARD)).toBe(true);
  });
});
