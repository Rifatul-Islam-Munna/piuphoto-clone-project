import { Grid3X3, Move } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { Slider } from "@/components/ui/slider";
import { cn } from "@/lib/utils";

export type WatermarkValue = {
  watermarkUrl?: string;
  watermarkPosition?: string;
  watermarkOpacity?: number;
  watermarkScale?: number;
};

type Props = {
  value: WatermarkValue;
  onChange: (patch: Partial<WatermarkValue>) => void;
  coverUrl?: string;
  logoUrl?: string;
  eventTitle?: string;
  footerText?: string;
  sponsorText?: string;
  whiteLabel?: boolean;
};

const positions = [
  ["top_left", "TL"],
  ["top_center", "TC"],
  ["top_right", "TR"],
  ["center_left", "CL"],
  ["center", "C"],  ["center_right", "CR"],
  ["bottom_left", "BL"],
  ["bottom_center", "BC"],
  ["bottom_right", "BR"],
] as const;

const anchorClass: Record<string, string> = {
  top_left: "left-4 top-4",
  top_center: "left-1/2 top-4 -translate-x-1/2",
  top_right: "right-4 top-4",
  center_left: "left-4 top-1/2 -translate-y-1/2",
  center: "left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2",
  center_right: "right-4 top-1/2 -translate-y-1/2",
  bottom_left: "bottom-4 left-4",
  bottom_center: "bottom-4 left-1/2 -translate-x-1/2",
  bottom_right: "bottom-4 right-4",
};

export default function WatermarkEditor({
  value,
  onChange,
  coverUrl,
  logoUrl,
  eventTitle,
  footerText,
  sponsorText,
  whiteLabel,
}: Props) {
  const position = value.watermarkPosition || "bottom_right";
  const opacity = value.watermarkOpacity ?? 0.7;  const scale = value.watermarkScale ?? 24;

  return (
    <div className="grid gap-5 xl:grid-cols-[minmax(0,1fr)_minmax(320px,0.8fr)]">
      <div className="space-y-5 rounded-2xl border bg-background p-4">
        <div className="flex items-start justify-between gap-3">
          <div>
            <Label className="text-base font-semibold">Watermark placement</Label>
            <p className="mt-1 text-xs text-muted-foreground">
              Pick a position, then tune size and opacity. Preview updates instantly.
            </p>
          </div>
          <Badge variant="secondary">Live preview</Badge>
        </div>

        <div className="grid grid-cols-3 gap-2 rounded-2xl bg-muted/40 p-2">
          {positions.map(([key, label]) => (
            <button
              key={key}
              type="button"
              aria-label={`Place watermark ${key.replace(/_/g, " ")}`}
              onClick={() => onChange({ watermarkPosition: key })}
              className={cn(
                "flex h-14 items-center justify-center rounded-xl border text-xs font-semibold transition-all duration-200",
                position === key
                  ? "border-primary bg-primary text-primary-foreground shadow-sm"
                  : "bg-background hover:border-primary/40 hover:bg-accent",
              )}
            >
              {label}
            </button>
          ))}
        </div>
        <Button
          type="button"
          variant={position === "tile" ? "default" : "outline"}
          className="w-full justify-start"
          onClick={() => onChange({ watermarkPosition: "tile" })}
        >
          <Grid3X3 className="mr-2 h-4 w-4" />
          Tile watermark across the preview
        </Button>

        <div className="space-y-3">
          <div className="flex items-center justify-between gap-3">
            <Label>Opacity</Label>
            <span className="text-sm font-semibold tabular-nums">
              {Math.round(opacity * 100)}%
            </span>
          </div>
          <Slider
            min={5}
            max={100}
            step={5}
            value={[Math.round(opacity * 100)]}
            onValueChange={([next]) =>
              onChange({ watermarkOpacity: Math.max(0.05, next / 100) })
            }
          />
        </div>

        <div className="space-y-3">
          <div className="flex items-center justify-between gap-3">
            <Label>Size</Label>            <span className="text-sm font-semibold tabular-nums">{scale}%</span>
          </div>
          <Slider
            min={5}
            max={80}
            step={1}
            value={[scale]}
            onValueChange={([next]) => onChange({ watermarkScale: next })}
          />
        </div>

        <div className="flex items-start gap-3 rounded-xl border bg-muted/30 p-3 text-xs text-muted-foreground">
          <Move className="mt-0.5 h-4 w-4 shrink-0" />
          <p>
            These settings are used on public store previews. Purchased files stay
            original resolution and are delivered without this watermark.
          </p>
        </div>
      </div>

      <div className="space-y-2">
        <Label className="text-base font-semibold">Preview</Label>
        <div className="relative aspect-[16/10] overflow-hidden rounded-2xl border bg-slate-900 shadow-sm">
          {coverUrl ? (
            <img
              src={coverUrl}
              alt="Gallery preview"
              className="absolute inset-0 h-full w-full object-cover"
            />
          ) : (
            <div className="absolute inset-0 bg-gradient-to-br from-slate-700 via-slate-800 to-slate-950" />
          )}          <div className="absolute inset-0 bg-black/35" />
          <div className="relative z-10 flex h-full flex-col justify-between p-5 text-white">
            <div>
              {logoUrl ? (
                <img src={logoUrl} alt="" className="max-h-9 max-w-28 object-contain" />
              ) : whiteLabel ? null : (
                <span className="text-sm font-bold tracking-wide">airpix</span>
              )}
            </div>
            <div>
              <p className="text-xl font-semibold sm:text-2xl">
                {eventTitle || "Event gallery"}
              </p>
              <p className="mt-1 max-w-sm text-xs text-white/75">
                {footerText || sponsorText || "Your branded live gallery"}
              </p>
            </div>
          </div>

          {value.watermarkUrl && position === "tile" ? (
            <div className="pointer-events-none absolute inset-0 z-20 grid grid-cols-3 grid-rows-2 place-items-center gap-4 p-5">
              {Array.from({ length: 6 }, (_, index) => (
                <img
                  key={index}
                  src={value.watermarkUrl}
                  alt=""
                  className="max-h-16 max-w-full object-contain"
                  style={{ opacity, width: `${Math.min(scale, 45)}%` }}
                />
              ))}
            </div>
          ) : value.watermarkUrl ? (
            <img
              src={value.watermarkUrl}
              alt="Watermark preview"              className={cn(
                "pointer-events-none absolute z-20 max-h-[42%] object-contain transition-all duration-200",
                anchorClass[position] || anchorClass.bottom_right,
              )}
              style={{ opacity, width: `${scale}%` }}
            />
          ) : (
            <div className="pointer-events-none absolute inset-x-5 top-1/2 z-20 -translate-y-1/2 rounded-xl border border-dashed border-white/35 bg-black/20 px-4 py-3 text-center text-xs text-white/75 backdrop-blur-sm">
              Upload a watermark above to preview placement here.
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
