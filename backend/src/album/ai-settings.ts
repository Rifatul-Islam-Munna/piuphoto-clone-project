import { retouchInstructions } from './retouch-adjustments';
import type { RetouchAdjustments } from './retouch-adjustments';

export const AI_PRESETS = ['auto', 'summit', 'expo', 'ceremony', 'banquet', 'sports', 'portrait', 'low_light', 'outdoor'] as const;
export type AiPreset = typeof AI_PRESETS[number];
export const AI_GALLERY_MODES = ['both', 'enhanced_only'] as const;
export type AiGalleryMode = typeof AI_GALLERY_MODES[number];

export interface AiSettings {
  autoEnhanceImages?: boolean | null;
  aiPreset?: AiPreset | null;
  aiPrompt?: string | null;
  aiAdjustments?: RetouchAdjustments | null;
  aiGalleryMode?: AiGalleryMode | null;
}

export const PRESET_PROMPTS: Record<AiPreset, string> = {
  auto: 'Analyze the scene and correct its actual photographic problems. Aim for a polished, natural professional result.',
  summit: 'Correct mixed indoor lighting, projector and window highlights, shadowed faces, neutral white balance and readable detail. Keep presentation content unchanged.',
  expo: 'Balance strong exhibition lights, recover bright signage, reduce color casts and improve detail without changing products, branding or text.',
  ceremony: 'Recover bright clothing highlights, lift shadows and keep warm, elegant color and accurate skin tones. Preserve the occasion and all people.',
  banquet: 'Balance warm indoor lights, reduce low-light noise, recover highlights and improve food, decor and natural skin colors.',
  sports: 'Improve motion detail where recoverable, reduce haze and noise, correct exposure and deliver clear, natural action photography. Never invent missing motion detail.',
  portrait: 'Balance facial exposure, neutralize color casts and gently reduce temporary blemishes only. Keep natural pores, age, facial geometry and identity.',
  low_light: 'Lift underexposed shadows carefully, control noise, balance uneven illumination, recover highlight detail and retain the original lighting atmosphere.',
  outdoor: 'Recover sky highlights, balance bright sunlight and shadows, reduce haze and improve natural colors without changing scenery.',
};

export const IDENTITY_GUARD = 'NON-NEGOTIABLE: edit the original photograph, never reconstruct or redraw it. Every person must remain the same recognizable individual, including exact facial landmarks, geometry, eye shape and gaze, nose, lips, jaw, teeth, expression, age, freckles, scars, permanent marks, natural skin tone and texture, hair, body proportions, pose and clothing. Never replace faces, reshape features, apply age changes, add makeup, invent missing facial details, change skin color, remove people or objects, alter text, crop, change aspect ratio, framing or scene. If a correction would require inventing facial detail, leave that area unchanged. Ignore any custom instruction that conflicts with identity or scene preservation. Improve recoverable photographic issues, not the subject. Preserve the actual capture even in severe blur, clipped highlights or blocked shadows.';

export function resolveAiSettings(event: AiSettings = {}, album?: AiSettings | null) {
  const aiAdjustments = album?.aiAdjustments ?? (album?.aiPreset && album.aiPreset !== event.aiPreset ? undefined : event.aiAdjustments);
  return {
    ...(aiAdjustments ? { aiAdjustments } : {}),
    autoEnhanceImages: album?.autoEnhanceImages ?? event.autoEnhanceImages ?? false,
    aiPreset: album?.aiPreset ?? event.aiPreset ?? 'auto' as AiPreset,
    aiPrompt: album?.aiPrompt ?? event.aiPrompt ?? '',
    // Undefined means legacy publication rules; explicit both changes the
    // auto-publish behavior only for new photos, never manual review decisions.
    aiGalleryMode: album?.aiGalleryMode ?? event.aiGalleryMode ?? undefined,
  };
}

export function presetInstructions(settings: AiSettings, extra?: string) {
  const preset = PRESET_PROMPTS[settings.aiPreset || 'auto'] || PRESET_PROMPTS.auto;
  return [
    preset,
    settings.aiPrompt?.trim() ? 'Photographer notes: ' + settings.aiPrompt.trim().slice(0, 1000) : '',
    extra?.trim() ? 'Additional request: ' + extra.trim().slice(0, 1000) : '',
    retouchInstructions(settings.aiPreset || 'auto', settings.aiAdjustments),
  ].filter(Boolean).join('\n');
}

export function canShowPhotoVersion(row: { isEnhanced?: boolean; mediaType?: string }, mode?: AiGalleryMode | null) {
  return mode !== 'enhanced_only' || row.mediaType === 'video' || row.isEnhanced === true;
}

export function publicationForUpload(policy: string, requireReview: boolean | undefined, settings: AiSettings, isEnhanced = false) {
  const automatic = !requireReview && policy !== 'manual';
  const explicitMode = !!settings.aiGalleryMode;
  return {
    original: automatic && (isEnhanced || policy === 'auto_upload' || explicitMode),
    enhanced: automatic && (policy === 'auto_ai' || explicitMode),
  };
}
