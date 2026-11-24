// Percentages are adaptive correction priorities/ceilings for the existing
// generative editor, not deterministic pixel-level slider measurements.
export const PHOTO_CONTROLS = {
  exposure: 'balance overall exposure, including backlit or dim images',
  highlights: 'recover clipped-looking highlights from existing detail',
  shadows: 'lift blocked shadows while retaining depth',
  whiteBalance: 'neutralize unwanted white-balance and mixed-light color casts',
  contrast: 'restore midtone separation and natural contrast',
  color: 'improve realistic color vibrance and tonal harmony without changing object colors',
  noise: 'reduce luminance and chroma noise without waxy textures',
  sharpness: 'restore useful edge and fine-detail clarity without halos',
  deblur: 'reduce mild camera shake or motion blur only where detail is recoverable',
  haze: 'reduce haze and veiling glare without changing the scene',
} as const;
export const PORTRAIT_CONTROLS = {
  blemish: 'soften only temporary blemishes, preserving permanent marks',
  forehead: 'soften harsh forehead wrinkle contrast, never erase age lines',
  eyeWrinkle: 'soften harsh eye-area wrinkle contrast, never reshape eyes',
  underEye: 'reduce excessive under-eye shadow without removing natural anatomy',
  texture: 'gently even distracting skin texture, retaining pores and fine detail',
} as const;

export type PhotoControl = keyof typeof PHOTO_CONTROLS;
export type PortraitControl = keyof typeof PORTRAIT_CONTROLS;
export type PortraitGroup = 'male' | 'female' | 'child';
export type RetouchAdjustments = {
  photo?: Partial<Record<PhotoControl, number>>;
  male?: Partial<Record<PortraitControl, number>>;
  female?: Partial<Record<PortraitControl, number>>;
  child?: { blemish?: number };
};
export const PHOTO_DEFAULTS: Record<PhotoControl, number> = {
  exposure: 85, highlights: 85, shadows: 80, whiteBalance: 90,
  contrast: 65, color: 60, noise: 65, sharpness: 65, deblur: 55, haze: 40,
};
export const ADULT_DEFAULTS: Record<PortraitControl, number> = {
  blemish: 20, forehead: 8, eyeWrinkle: 8, underEye: 12, texture: 8,
};
export const ADULT_LIMITS: Record<PortraitControl, number> = {
  blemish: 40, forehead: 25, eyeWrinkle: 25, underEye: 30, texture: 20,
};
export const CHILD_DEFAULTS = { blemish: 0 };
export const CHILD_LIMITS = { blemish: 15 };
export const PRESET_PHOTO_OVERRIDES: Record<string, Partial<Record<PhotoControl, number>>> = {
  summit: { highlights: 95, whiteBalance: 95, shadows: 85, color: 45 },
  expo: { highlights: 95, whiteBalance: 95, color: 50, sharpness: 75 },
  ceremony: { highlights: 95, shadows: 75, color: 65 },
  banquet: { whiteBalance: 95, shadows: 85, noise: 85 },
  sports: { sharpness: 85, deblur: 90, noise: 75, haze: 60 },
  portrait: { contrast: 50, color: 50, sharpness: 50, deblur: 40 },
  low_light: { exposure: 95, shadows: 95, noise: 95, whiteBalance: 95, sharpness: 55 },
  outdoor: { highlights: 95, shadows: 90, haze: 75, color: 65 },
};

function mergeControls<K extends string>(
  defaults: Record<K, number>,
  custom: Partial<Record<K, number>> | undefined,
  limits: Record<K, number> | number,
): Record<K, number> {
  const result = { ...defaults };
  for (const key of Object.keys(defaults) as K[]) {
    const value = custom?.[key];
    if (typeof value === 'number' && Number.isFinite(value)) {
      result[key] = Math.min(typeof limits === 'number' ? limits : limits[key], Math.max(0, Math.round(value)));
    }
  }
  return result;
}

export function resolveRetouchAdjustments(preset: string, custom?: RetouchAdjustments | null) {
  const photo = { ...PHOTO_DEFAULTS, ...(PRESET_PHOTO_OVERRIDES[preset] || {}) };
  return {
    photo: mergeControls(photo, custom?.photo, 100),
    male: mergeControls(ADULT_DEFAULTS, custom?.male, ADULT_LIMITS),
    female: mergeControls(ADULT_DEFAULTS, custom?.female, ADULT_LIMITS),
    child: mergeControls(CHILD_DEFAULTS, custom?.child, CHILD_LIMITS),
  };
}

export function retouchInstructions(preset: string, custom?: RetouchAdjustments | null) {
  const resolved = resolveRetouchAdjustments(preset, custom);
  const describe = <K extends string>(labels: Record<K, string>, values: Record<K, number>) =>
    (Object.keys(labels) as K[]).map(key => values[key] === 0
      ? labels[key] + ': OFF (do not apply this correction)'
      : labels[key] + ': up to ' + values[key] + '%').join('; ');
  return [
    'ADJUSTMENT PRIORITIES: percentages are maximum relative editing strengths, not mandatory changes or exact pixel values. Diagnose each defect first, apply only the necessary correction, leave already-correct regions alone. Zero disables that correction; these settings override general editing suggestions and photographer notes, but never override identity preservation.',
    'Global photographic corrections: ' + describe(PHOTO_CONTROLS, resolved.photo) + '.',
    'Adult male portrait: ' + describe(PORTRAIT_CONTROLS, resolved.male) + '.',
    'Adult female portrait: ' + describe(PORTRAIT_CONTROLS, resolved.female) + '.',
    'Portrait profiles apply independently to clearly appropriate subjects only. If age or adult presentation is uncertain, use only global photographic corrections. Do not infer identity, gender or age to force an edit. No face reshaping, body retouching, age reduction, makeup, artificial eye whitening or skin-tone changes.',
    'Children: ' + describe({ blemish: PORTRAIT_CONTROLS.blemish }, resolved.child) + '. No wrinkle, skin smoothing, under-eye, beauty or shape edits for children. Preserve their natural appearance and age.',
  ].join('\n');
}
