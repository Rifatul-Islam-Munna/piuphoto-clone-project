import sharp from 'sharp';

const SAMPLE_SIZE = 256;
export const SOURCE_COLOR_REJECTION_MESSAGE = 'AI result changed original colors. Original retained. Please retry.';

async function sample(file: string) {
  return sharp(file, { limitInputPixels: 150_000_000 }).rotate()
    .resize(SAMPLE_SIZE, SAMPLE_SIZE, { fit: 'fill' })
    .removeAlpha().toColourspace('srgb').raw().toBuffer();
}

/** Detects large, localized warm/dark color regressions against the source.
 * This is a conservative color comparison, not a face or skin classifier.
 * It deliberately ignores tiny changes and near-black/clipped source regions.
 */
export async function hasWarmColorRegression(sourceFile: string, resultFile: string): Promise<boolean> {
  const [source, result] = await Promise.all([sample(sourceFile), sample(resultFile)]);
  const mask = new Uint8Array(SAMPLE_SIZE * SAMPLE_SIZE);
  for (let pixel = 0; pixel < mask.length; pixel += 1) {
    const i = pixel * 3;
    const [r, g, b] = [source[i], source[i + 1], source[i + 2]];
    const luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b;
    const chroma = (Math.max(r, g, b) - Math.min(r, g, b)) / Math.max(1, r, g, b);
    // Reference only visible, modestly warm source colors. Never infer a
    // supposed "true complexion" from a different person or a colored scene.
    if (luminance < 40 || luminance > 238 || r < g - 3 || g < b - 5 ||
        r - b < 6 || chroma > 0.7) continue;
    const [rr, rg, rb] = [result[i], result[i + 1], result[i + 2]];
    const after = 0.2126 * rr + 0.7152 * rg + 0.0722 * rb;
    const sourceWarmth = (r - b) / Math.max(1, r + g + b);
    const resultWarmth = (rr - rb) / Math.max(1, rr + rg + rb);
    const warmthChange = resultWarmth - sourceWarmth;
    const afterChroma = (Math.max(rr, rg, rb) - Math.min(rr, rg, rb)) / Math.max(1, rr, rg, rb);
    const darkerAndWarmer = after < luminance * 0.85 && luminance - after > 18 && warmthChange > 0.035;
    // A neutral privacy mask is not a tanned/warmed replacement color.
    const muchDarker = after < luminance * 0.75 && luminance - after > 30 &&
      resultWarmth >= sourceWarmth - 0.005 && afterChroma > 0.04;
    const orangeCast = warmthChange > 0.09 && afterChroma - chroma > 0.15;
    if (darkerAndWarmer || muchDarker || orangeCast) mask[pixel] = 1;
  }

  // Require a solid region rather than JPEG noise, a few blemishes or a thin
  // alignment edge. Local components keep one bad face from hiding in averages.
  for (let start = 0; start < mask.length; start += 1) {
    if (!mask[start]) continue;
    const stack = [start];
    mask[start] = 0;
    let count = 0;
    let left = SAMPLE_SIZE, right = 0, top = SAMPLE_SIZE, bottom = 0;
    while (stack.length) {
      const current = stack.pop()!;
      const x = current % SAMPLE_SIZE, y = Math.floor(current / SAMPLE_SIZE);
      count += 1;
      left = Math.min(left, x); right = Math.max(right, x);
      top = Math.min(top, y); bottom = Math.max(bottom, y);
      const neighbors = [
        x > 0 ? current - 1 : -1,
        x < SAMPLE_SIZE - 1 ? current + 1 : -1,
        y > 0 ? current - SAMPLE_SIZE : -1,
        y < SAMPLE_SIZE - 1 ? current + SAMPLE_SIZE : -1,
      ];
      for (const next of neighbors) {
        if (next >= 0 && mask[next]) { mask[next] = 0; stack.push(next); }
      }
    }
    const width = right - left + 1, height = bottom - top + 1;
    if (count >= 48 && width >= 6 && height >= 6 && count / (width * height) >= 0.4) return true;
  }
  return false;
}
