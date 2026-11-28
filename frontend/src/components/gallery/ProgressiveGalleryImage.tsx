import { useEffect, useRef, useState } from "react";
import { ImageOff } from "lucide-react";

type Props = {
  src: string;
  alt: string;
  placeholderSrc?: string;
  fallbackSrc?: string;
  className?: string;
  containerClassName?: string;
  loading?: "lazy" | "eager";
};

function ProgressiveImage({ src, alt, placeholderSrc, fallbackSrc, className = "", containerClassName = "", loading = "lazy" }: Props) {
  const [activeSrc, setActiveSrc] = useState(src);
  const [phase, setPhase] = useState<"loading" | "loaded" | "error">("loading");
  const imageRef = useRef<HTMLImageElement>(null);

  useEffect(() => {
    const img = imageRef.current;
    if (img?.complete && img.naturalWidth > 0) setPhase("loaded");
  }, [activeSrc]);

  const onError = () => {
    if (fallbackSrc && fallbackSrc !== activeSrc) {
      setPhase("loading");
      setActiveSrc(fallbackSrc);
    } else {
      setPhase("error");
    }
  };
  const showPreview = phase === "loading" && placeholderSrc && placeholderSrc !== activeSrc;

  return (
    <div className={`relative overflow-hidden bg-muted ${phase !== "loaded" ? "min-h-32" : ""} ${containerClassName}`} aria-busy={phase === "loading"}>
      {phase === "loading" && (
        <div aria-hidden="true" className="pointer-events-none absolute inset-0 overflow-hidden bg-muted">
          <div className="absolute inset-0 animate-pulse bg-gradient-to-br from-zinc-200 via-zinc-100 to-zinc-300 dark:from-zinc-800 dark:via-zinc-700 dark:to-zinc-900 motion-reduce:animate-none" />
          {showPreview && (
            <img src={placeholderSrc} alt="" loading={loading} decoding="async"
              className="absolute inset-0 h-full w-full scale-110 object-cover blur-xl"
              onError={(event) => { event.currentTarget.style.visibility = "hidden"; }}
            />
          )}
        </div>
      )}
      {phase === "error" ? (
        <div role="img" aria-label={alt + " unavailable"} className="flex min-h-32 w-full flex-col items-center justify-center gap-1 bg-muted px-2 py-6 text-xs text-muted-foreground">
          <ImageOff className="h-5 w-5" /> Photo unavailable
        </div>
      ) : (
        <img ref={imageRef} src={activeSrc} alt={alt} loading={loading} decoding="async"
          onLoad={() => setPhase("loaded")} onError={onError}
          className={`${className} transition-[opacity,filter,transform] duration-300 motion-reduce:transition-none ${phase === "loaded" ? "opacity-100 blur-0" : "opacity-0 blur-xl"}`}
        />
      )}
    </div>
  );
}

export function ProgressiveGalleryImage(props: Props) {
  // Reset the loading/fallback state when a new R2 URL or lightbox photo arrives.
  return <ProgressiveImage key={JSON.stringify([props.src, props.fallbackSrc, props.placeholderSrc])} {...props} />;
}
