import sharp from 'sharp';

export interface PhotoFinishingOptions {
  exposure: number;
  shadows: number;
  color: number;
  lowLight: boolean;
}

const INPUT_OPTIONS = { limitInputPixels: 150_000_000 };

async function lightMetrics(file: string) {
  const { data, info } = await sharp(file, INPUT_OPTIONS)
    .rotate().resize(192, 192, { fit: 'inside', withoutEnlargement: true })
    .removeAlpha().toColourspace('srgb').raw().toBuffer({ resolveWithObject: true });
  const luminance: number[] = [];
  let visible = 0;
  for (let i = 0; i < data.length; i += info.channels) {
    const value = 0.2126 * data[i] + 0.7152 * data[i + 1] + 0.0722 * data[i + 2];
    // Exclude near-black backgrounds and light sources from the subject estimate.
    if (value >= 8 && value < 245) luminance.push(value);
    if (value >= 8) visible += 1;
  }
  luminance.sort((a, b) => a - b);
  const percentile = (fraction: number) => luminance[Math.floor((luminance.length - 1) * fraction)] || 0;
  return { median: percentile(0.5), upper: percentile(0.75), visible: visible / (info.width * info.height) };
}

/** Finishes an under-corrected low-light result without redrawing any content.
 * Returns false when the AI already corrected exposure, controls are off, or
 * the source does not contain enough evidence for a conservative correction.
 */
export async function finishLowLight(
  sourceFile: string,
  resultFile: string,
  destination: string,
  options: PhotoFinishingOptions,
): Promise<boolean> {
  const clamp = (value: number) => Number.isFinite(value) ? Math.max(0, Math.min(100, value)) : 0;
  // A tonal curve affects both exposure and shadows. Either OFF control vetoes it.
  const strength = Math.min(clamp(options.exposure), clamp(options.shadows)) / 100;
  if (!strength) return false;
  const source = await lightMetrics(sourceFile);
  const explicit = options.lowLight === true;
  if (source.visible < 0.1 || source.median < 12 ||
      source.median >= (explicit ? 85 : 65) || source.upper >= (explicit ? 115 : 90)) return false;

  const result = await lightMetrics(resultFile);
  if (result.median < 8) return false;
  // A relative target alone stays too dark for severely underexposed sources.
  // Use a bounded readable-midtone floor, with a stronger explicit low-light pass.
  const target = Math.max(explicit ? 88 : 64,
    Math.min(explicit ? 112 : 96, source.median * (explicit ? 1.55 : 1.4) + 12));
  // Do not brighten an AI result that already reached the source-relative target.
  if (result.median >= target - 4) return false;
  const adjustedTarget = result.median + (target - result.median) * strength;
  const gamma = Math.min(explicit ? 2.2 : 1.8,
    Math.log(result.median / 255) / Math.log(adjustedTarget / 255));
  if (gamma < 1.03) return false;

  // A bounded gamma curve lifts recoverable midtones while keeping black/white
  // endpoints. No resize, sharpening, face reconstruction or hue rotation.
  // Do not add global saturation: it also pushes otherwise-correct faces
  // toward orange/brown. Color controls remain part of the AI editing request;
  // this fallback only lifts exposure with a non-darkening channel curve.
  await sharp(resultFile, INPUT_OPTIONS).rotate().gamma(1, gamma).png().toFile(destination);
  const finished = await lightMetrics(destination);
  return finished.median >= result.median + 3;
}
