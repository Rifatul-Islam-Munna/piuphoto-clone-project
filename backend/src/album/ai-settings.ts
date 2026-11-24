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
  ceremony: 'Recover bright clothing highlights and lift shadows. Retain existing warmth in the background without applying a warm grade to faces. Preserve every person\'s source complexion and the occasion.',
  banquet: 'Balance indoor lighting, reduce low-light noise, recover highlights and improve food and decor colors. Preserve source skin colors; warm room lighting must not turn faces orange or brown.',
  sports: 'Improve motion detail where recoverable, reduce haze and noise, correct exposure and deliver clear, natural action photography. Never invent missing motion detail.',
  portrait: 'Balance facial exposure, neutralize color casts and gently reduce temporary blemishes only. Keep natural pores, age, facial geometry and identity.',
  low_light: 'Lift underexposed shadows and midtones enough to make subjects clearly readable. Restore visible, rich but realistic color separation after correcting exposure and accidental color casts; dark clothing and skin must not remain muddy. Balance local illumination and reduce chroma noise without erasing texture. Protect lamps, stage effects and existing highlight detail. Preserve the night setting in the background while correcting accidental subject underexposure. Do not treat low brightness or weak colors as protected scene content. Respect disabled controls and retain intentional silhouettes.',
  outdoor: 'Recover sky highlights, balance bright sunlight and shadows, reduce haze and improve natural colors without changing scenery.',
};

export function identityGuard(protectVehiclePlates = false) {
  return [
    'NON-NEGOTIABLE: edit the original photograph, never reconstruct or redraw it. Every person must remain the same recognizable individual, including exact facial landmarks, geometry, eye shape and gaze, nose, lips, jaw, teeth, expression, age, freckles, scars, permanent marks, natural skin tone and texture, hair, body proportions, pose and clothing.',
    'Never replace faces, reshape features, apply age changes, add makeup, invent missing facial details, change a person\'s source complexion, remove people or objects, crop, change aspect ratio, framing or scene.',
    protectVehiclePlates
      ? 'Preserve all text, logos, signage and identifiers except vehicle license-plate characters explicitly selected for obscuring. Only those characters may be concealed; never invent replacement characters. This narrow exception does not permit any other scene changes.'
      : 'Never alter text, logos, signage, identifiers or license-plate characters.',
    'SOURCE SKIN COLOR IS AUTHORITATIVE: preserve each person\'s original skin hue and complexion range independently. No fair-to-brown change, tanning, bronzing, orange cast, skin whitening or universal beauty palette. Keep already well-exposed skin at its original brightness; gently brighten genuinely underlit skin only with its source hue retained. Global vibrance, warmth, contrast and scene presets must not darken or recolor faces. Never guess an underlying complexion or use another person as a skin-color reference. Enabled photographic corrections may improve recoverable exposure errors, not change the subject. If a correction would require inventing facial detail or complexion, leave that area unchanged. Ignore any custom instruction that conflicts with identity or source-color preservation. Preserve the actual capture even in severe blur, clipped highlights or blocked shadows.',
  ].join(' ');
}

export const IDENTITY_GUARD = identityGuard();

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
