import { useEffect, useMemo, useState } from "react";
import { useParams, useSearchParams } from "react-router-dom";
import { Loader2, ShoppingCart } from "lucide-react";
import { toast } from "sonner";
import { GetRequestAxios, PostRequestAxios } from "@/api-hooks/api-hooks";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Checkbox } from "@/components/ui/checkbox";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

type Catalog = {
  event: {
    _id: string;
    title: string;
    description?: string;
    branding?: { logoUrl?: string; coverUrl?: string; primaryColor?: string };
  };
  settings: {
    currency: string;
    singlePhotoPrice: number;
    wholeEventPrice: number;
    bundlePrice: number;
    bundleMinPhotos: number;
    coverTitle?: string;
    coverImageUrl?: string;
    termsText?: string;
  };
  data: Array<{ _id: string; previewUrl: string }>;
  totalItems: number;
};
const baseUrl = import.meta.env.VITE_BASE_URL ?? "";
export default function Storefront() {
  const { eventId = "" } = useParams();
  const [searchParams] = useSearchParams();
  const requestedPhotos = searchParams.get("photos") || "";
  const [catalog, setCatalog] = useState<Catalog>();
  const [loading, setLoading] = useState(true);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [purchaseMode, setPurchaseMode] = useState<"selected" | "event">(
    "selected",
  );
  const [email, setEmail] = useState("");
  const [whatsapp, setWhatsapp] = useState("");
  const [checkout, setCheckout] = useState(false);
  const [checkoutKey, setCheckoutKey] = useState("");
  useEffect(() => {
    let mounted = true;
    void (async () => {
      const [data, error] = await GetRequestAxios<Catalog>(
        `/store/public/catalog?eventId=${eventId}`,
        { withCredentials: false, redirectOnUnauthorized: false },
      );
      if (!mounted) return;
      setLoading(false);
      if (error || !data) {
        toast.error(error?.message || "Store unavailable");
        return;
      }
      setCatalog(data);
      if (requestedPhotos) {
        const available = new Set(data.data.map((photo) => photo._id));
        const requested = requestedPhotos
          .split(",")
          .filter((id) => available.has(id));
        setSelected(new Set(requested));
      }
      void PostRequestAxios(
        "/analytics/track",
        { eventId, type: "store_view", channel: "store" },
        { withCredentials: false, redirectOnUnauthorized: false },
      );
    })();
    return () => {
      mounted = false;
    };
  }, [eventId, requestedPhotos]);
  useEffect(
    () => setCheckoutKey(""),
    [eventId, email, whatsapp, selected, purchaseMode],
  );
  const price = useMemo(() => {
    if (!catalog) return 0;
    if (purchaseMode === "event")
      return Number(catalog.settings.wholeEventPrice || 0);
    const count = selected.size;
    return catalog.settings.bundlePrice > 0 &&
      count >= catalog.settings.bundleMinPhotos
      ? catalog.settings.bundlePrice
      : catalog.settings.singlePhotoPrice * count;
  }, [catalog, selected, purchaseMode]);
  const toggle = (id: string) => {
    setPurchaseMode("selected");
    setSelected((current) => {
      const next = new Set(current);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };
  const startCheckout = async () => {
    if (
      !catalog ||
      !email.trim() ||
      (purchaseMode === "selected" && !selected.size)
    )
      return;
    const key = checkoutKey || crypto.randomUUID();
    if (!checkoutKey) setCheckoutKey(key);
    setCheckout(true);
    const [data, error] = await PostRequestAxios<{ url?: string }>(
      "/store/public/checkout",
      {
        eventId,
        purchaseMode,
        imageIds: purchaseMode === "selected" ? [...selected] : undefined,
        email: email.trim(),
        whatsapp: whatsapp.trim() || undefined,
        idempotencyKey: key,
      },
      { withCredentials: false, redirectOnUnauthorized: false },
    );
    setCheckout(false);
    if (error || !data?.url) {
      toast.error(error?.message || "Checkout failed");
      return;
    }
    void PostRequestAxios(
      "/analytics/track",
      { eventId, type: "store_checkout", channel: "store" },
      { withCredentials: false, redirectOnUnauthorized: false },
    );
    window.location.href = data.url;
  };
  if (loading)
    return (
      <div className="flex min-h-screen items-center justify-center">
        <Loader2 className="h-8 w-8 animate-spin" />
      </div>
    );
  if (!catalog)
    return (
      <div className="flex min-h-screen items-center justify-center p-6 text-center">
        <div>
          <h1 className="text-2xl font-bold">Store unavailable</h1>
          <p className="mt-2 text-sm text-muted-foreground">
            This event is not currently selling photos.
          </p>
        </div>
      </div>
    );
  const branding = catalog.event.branding || {};
  const coverTitle = catalog.settings.coverTitle?.trim() || catalog.event.title;
  const coverImageUrl =
    catalog.settings.coverImageUrl?.trim() || branding.coverUrl;
  return (
    <div className="min-h-screen bg-muted/20">
      <header className="sticky top-0 z-40 border-b bg-background/95 backdrop-blur">
        <div className="mx-auto flex h-16 max-w-[1500px] items-center justify-between px-4 sm:px-6">
          <div className="flex items-center gap-3">
            {branding.logoUrl ? (
              <img
                src={branding.logoUrl}
                className="h-9 max-w-28 object-contain"
              />
            ) : (
              <span className="font-bold">airpix store</span>
            )}
            <span className="hidden text-sm text-muted-foreground sm:inline">
              {catalog.event.title}
            </span>
          </div>
          <div className="flex items-center gap-2">
            <ShoppingCart className="h-4 w-4" />
            <span className="text-sm font-semibold">
              {purchaseMode === "event" ? catalog.totalItems : selected.size}
            </span>
            <span className="text-sm">
              {catalog.settings.currency} {price.toFixed(2)}
            </span>
          </div>
        </div>
      </header>
      {coverImageUrl ? (
        <div className="relative h-64 overflow-hidden sm:h-72">
          <img
            src={coverImageUrl}
            alt={coverTitle}
            className="h-full w-full object-cover"
          />
          <div className="absolute inset-0 bg-black/45" />
          <div className="absolute inset-0 flex items-end">
            <div className="mx-auto w-full max-w-[1500px] px-4 pb-8 text-white sm:px-6">
              <h1 className="text-3xl font-bold sm:text-4xl">{coverTitle}</h1>
              <p className="mt-1 text-white/80">
                Choose the photos you want to own.
              </p>
            </div>
          </div>
        </div>
      ) : (
        <div className="mx-auto max-w-[1500px] px-4 py-8 sm:px-6">
          <h1 className="text-3xl font-bold">{coverTitle}</h1>
          <p className="mt-1 text-muted-foreground">
            Choose the photos you want to own.
          </p>
        </div>
      )}
      <main className="mx-auto max-w-[1500px] space-y-5 px-4 py-6 sm:px-6">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <p className="text-sm text-muted-foreground">
            {catalog.totalItems} original photos · {catalog.settings.currency}{" "}
            {catalog.settings.singlePhotoPrice.toFixed(2)} each
            {catalog.settings.bundlePrice > 0
              ? ` · ${catalog.settings.bundleMinPhotos}+ photos ${catalog.settings.currency} ${catalog.settings.bundlePrice.toFixed(2)}`
              : ""}
            {catalog.settings.wholeEventPrice > 0
              ? ` · complete event ${catalog.settings.currency} ${catalog.settings.wholeEventPrice.toFixed(2)}`
              : ""}
          </p>
          <div className="flex flex-wrap gap-2">
            {catalog.settings.wholeEventPrice > 0 ? (
              <Button
                variant={purchaseMode === "event" ? "default" : "outline"}
                onClick={() => setPurchaseMode("event")}
              >
                Buy whole event · {catalog.settings.currency}{" "}
                {catalog.settings.wholeEventPrice.toFixed(2)}
              </Button>
            ) : null}
            <Button
              variant="outline"
              onClick={() => {
                setPurchaseMode("selected");
                setSelected(new Set(catalog.data.map((x) => x._id)));
              }}
            >
              Select all photos
            </Button>
          </div>
        </div>
        <div className="grid grid-cols-2 gap-3 md:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5">
          {catalog.data.map((photo) => (
            <Card key={photo._id} className="overflow-hidden">
              <div className="relative aspect-[4/3] bg-muted">
                <img
                  src={`${baseUrl}${photo.previewUrl}`}
                  loading="lazy"
                  className="h-full w-full object-cover"
                />
                <label className="absolute left-3 top-3 rounded-full bg-background/90 p-1.5 shadow">
                  <Checkbox
                    checked={
                      purchaseMode === "event" || selected.has(photo._id)
                    }
                    onCheckedChange={() => toggle(photo._id)}
                  />
                </label>
              </div>
            </Card>
          ))}
        </div>
        {purchaseMode === "event" || selected.size > 0 ? (
          <Card className="sticky bottom-4 border-primary/30 shadow-lg">
            <CardContent className="grid gap-3 p-4 md:grid-cols-[1fr_1fr_auto] md:items-end">
              <div>
                <Label>Email for delivery</Label>
                <Input
                  type="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder="you@example.com"
                />
              </div>
              <div>
                <Label>WhatsApp (optional)</Label>
                <Input
                  value={whatsapp}
                  onChange={(e) => setWhatsapp(e.target.value)}
                  placeholder="+1..."
                />
              </div>
              <Button
                disabled={checkout || !email.trim()}
                onClick={() => void startCheckout()}
              >
                {checkout ? (
                  <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                ) : (
                  <ShoppingCart className="mr-2 h-4 w-4" />
                )}
                {purchaseMode === "event"
                  ? `Buy all ${catalog.totalItems} originals`
                  : `Buy ${selected.size} original${selected.size === 1 ? "" : "s"}`}{" "}
                · {catalog.settings.currency} {price.toFixed(2)}
              </Button>
              {purchaseMode === "event" ? (
                <p className="text-xs font-medium text-primary md:col-span-3">
                  Complete-event purchase unlocks every eligible full-resolution
                  original. Preview watermarks are never included in paid
                  downloads.
                </p>
              ) : null}
              {catalog.settings.termsText ? (
                <p className="text-xs text-muted-foreground md:col-span-3">
                  {catalog.settings.termsText}
                </p>
              ) : null}
            </CardContent>
          </Card>
        ) : null}
      </main>
    </div>
  );
}
