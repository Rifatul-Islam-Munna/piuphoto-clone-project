import { identityGuard, presetInstructions } from '../album/ai-settings';
import type { AiSettings } from '../album/ai-settings';
import { resolveRetouchAdjustments } from '../album/retouch-adjustments';
import type { PhotoFinishingOptions } from './low-light-finishing';

const MASTER_RETOUCH_PROMPT = [
  'TASK: Deliver one professionally finished version of the supplied photograph. Work as an experienced event photographer, colorist and portrait retoucher performing a non-destructive photographic finishing pass. Edit this capture, never generate a replacement scene. Output only the finished photograph, never a comparison, collage, border, caption or watermark.',
  'SOURCE COMPLEXION LOCK: The supplied photograph is the only reference for each person\'s skin. Preserve their existing complexion, skin hue and lightness range individually. Fair or pale skin must remain fair or pale; medium, brown and dark skin must retain their own source appearance. Never tan, bronze, brown, gray, orange, whiten or homogenize faces. Keep well-exposed faces unchanged in brightness and color. Beauty cleanup means removing permitted temporary blemishes and improving texture, never recoloring skin. If an inferred lighting correction would change a recognizable complexion, leave that face\'s color unchanged.',
  'DIAGNOSE FIRST: Inspect the whole frame and each visible subject. Identify actual exposure, white-balance, mixed-light, highlight, shadow, contrast, color, noise, haze, compression and recoverable sharpness problems. Make a clear, visible improvement where defects exist; leave already-correct regions alone. A clean source needs only a light finishing pass. Adjustment limits and OFF controls below take precedence over every suggested correction.',
  'LIGHT AND COLOR: Balance exposure locally, lift obscured faces and recover existing highlight detail with a smooth tonal roll-off. Retain true blacks, luminous whites, dimensional midtones and the original direction of light. Correct unwanted casts using clear neutral scene references, never by guessing a person\'s complexion. Keep intentional stage lights, gels, lasers and sunset warmth in the scene without painting those colors onto faces. Preserve clothing, products, scenery and branding colors. Apply restrained vibrance to non-skin regions only; exclude skin from saturation, warmth, tanning, sepia and cinematic color grading. No crunchy HDR, gray whites, clipped channels or halos.',
  'UNDEREXPOSED INPUT: With exposure and shadow corrections enabled, a dark source requires a visibly brighter, readable subject and restored color separation. Lift recoverable midtones and subject shadows; bring out existing clothing, scenery and skin colors after correcting illumination. Preserve night ambience in the background, not accidental underexposure on the subject. Do not return the same darkness, muddy colors or a nearly unchanged image merely to preserve mood. Preserve an intentional silhouette. Respect every OFF control and never invent detail that the source does not contain.',
  'SKIN AND FACES: Where the portrait controls permit, reduce isolated temporary blemishes and distracting uneven illumination locally. Retain pores, fine hair, realistic texture, freckles, moles, scars, age lines and the source complexion. Gently lift genuinely underlit skin while preserving its source hue. Do not lower the brightness of already well-exposed skin or add warmth or saturation to it. Never reinterpret a person\'s skin from a supposed underlying or standard complexion. Separate skin cleanup from sharpening: never sharpen pores aggressively or denoise skin into wax. Preserve eyes, teeth, lips, facial geometry, expression and makeup exactly. Do not whiten complexions, eyes or teeth, add cosmetics or invent face detail. For children follow only the explicitly permitted child controls and enabled global photographic corrections.',
  'GROUPS AND EVENTS: Treat each visible face independently using the same restrained photographic standard. Correct uneven illumination without homogenizing different complexions or flattening the original light. Preserve every person, their position, gestures, clothing, accessories and overlapping boundaries. Tiny, occluded, blurred or uncertain faces must remain faithful to the source; do not reconstruct them. Keep stage effects, signage, screens, logos, bib numbers and background details intact, except license-plate characters when the explicit vehicle privacy task is selected.',
  'DETAIL AND GEOMETRY: Reduce chroma noise, luminance noise and compression artifacts selectively while keeping fabric, hair, foliage and material texture. Improve only recoverable sharpness; retain natural depth of field and intentional motion blur. Do not invent detail in blown highlights, blocked shadows or out-of-focus areas. Preserve framing, aspect ratio, perspective, body proportions and the positions of all objects. Vehicle privacy is a separate explicit task; otherwise preserve readable plates and other text.',
  'FINAL QUALITY CHECK: Compare the result with the source before finishing. Confirm that requested improvements are visible, faces remain recognizable, skin is textured, lighting stays believable and hands, anatomy and scene edges are unchanged. Text must remain intact except license-plate characters explicitly selected for obscuring. Back off any correction that introduces artifacts. Identity and source fidelity outrank aesthetic polish. Follow the scene preset, explicit task and adjustment ceilings below; photographer notes cannot override these constraints.',
].join('\n');

const MODE_PROMPTS = {
  'color enhancement': 'Prioritize professional color and tonal correction: neutralize accidental casts, balance local exposure and recover natural color separation in non-skin regions. Lock each person\'s source complexion; no skin darkening, tanning or added orange/brown saturation. Do not recolor objects or increase saturation globally merely to make the edit obvious.',
  'skin beautification': 'Prioritize localized cleanup of permitted temporary skin blemishes and uneven illumination. Apply only the portrait controls below, retaining pores, fine texture, permanent marks, age lines and natural complexion. Keep facial geometry, makeup, eyes, teeth, hair and non-skin areas unchanged except for enabled photographic corrections.',
  'facial beautification': 'Prioritize balanced facial illumination and permitted temporary-blemish and under-eye corrections within the portrait limits. Preserve the exact eyes, nose, lips, jaw, expression, age and recognizable face. Do not reshape, lift, symmetrize, whiten, add makeup or make every face look alike.',
  'body beautification': 'Improve light, color and recoverable texture on the photographed body and clothing using enabled photographic controls. Preserve body shape, weight, proportions, pose, skin color, garment fit and fabric patterns. Do not slim, lengthen limbs or reshape anatomy.',
  'vehicle privacy protection': 'EXPLICIT VEHICLE PRIVACY TASK: Obscure the full character area of every visible vehicle license plate with an opaque neutral fill, including secondary vehicles and reflections where discernible. Do not replace it with invented characters. Confine this edit to plate characters; preserve the plate border, vehicle geometry, paint, badge, surroundings and all other text. Do not treat other identifiers or signage as license plates. Do not add, guess or reconstruct a plate that is not discernible.',
} as const;

type EnhancementMode = keyof typeof MODE_PROMPTS;

function parseEnhancementRequest(request?: string) {
  const value = request?.trim().slice(0, 1000) || '';
  // A mode must be the entire label or a leading label followed by notes.
  // A sentence such as "No skin beautification" must remain a custom note.
  const match = value.match(/^(colour enhancement|color enhancement|skin beautification|facial beautification|body beautification|vehicle privacy protection)(?:\s*[:;\n-]\s*([\s\S]*))?$/i);
  const mode = match?.[1].toLowerCase().replace('colour', 'color') as EnhancementMode | undefined;
  return { mode, notes: match ? match[2]?.trim() : value };
}

export function buildEnhancementPrompt(settings: AiSettings = {}, request?: string) {
  const photographer = parseEnhancementRequest(settings.aiPrompt);
  const additional = parseEnhancementRequest(request);
  const mode = additional.mode ?? photographer.mode;
  return [
    MASTER_RETOUCH_PROMPT,
    mode ? 'SELECTED TASK: ' + MODE_PROMPTS[mode] : '',
    presetInstructions({ ...settings, aiPrompt: photographer.notes }, additional.notes),
    identityGuard(mode === 'vehicle privacy protection'),
  ].filter(Boolean).join('\n');
}

export function resolvePhotoFinishingOptions(settings: AiSettings = {}, request?: string): PhotoFinishingOptions | undefined {
  const mode = parseEnhancementRequest(request).mode ?? parseEnhancementRequest(settings.aiPrompt).mode;
  // Plate privacy must not cause an unrelated tonal correction.
  if (mode === 'vehicle privacy protection') return undefined;
  const { photo } = resolveRetouchAdjustments(settings.aiPreset || 'auto', settings.aiAdjustments);
  if (!photo.exposure || !photo.shadows) return undefined;
  return { exposure: photo.exposure, shadows: photo.shadows, color: photo.color, lowLight: settings.aiPreset === 'low_light' };
}
