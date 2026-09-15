import { type ReactNode, useEffect, useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { CreditCard, ExternalLink, Image as ImageIcon, Loader2, Save, Send, ShoppingBag } from "lucide-react";
import { toast } from "sonner";
import PlannerLayout from "./PlannerLayout";
import { PatchRequestAxios } from "@/api-hooks/api-hooks";
import { useQueryWrapper } from "@/api-hooks/react-query-wrapper";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Checkbox } from "@/components/ui/checkbox";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Switch } from "@/components/ui/switch";

type EventRow = { _id: string; title: string };
type Album = { _id: string; title: string };
type SalePhoto = {
  _id: string;
  imageUrl: string;
  isForSale?: boolean;
  albumId?: { _id: string; title?: string } | string;
};
type StoreSettings = {
  enabled: boolean;
  currency: string;
  singlePhotoPrice: number;
  bundlePrice: number;
  bundleMinPhotos: number;
  downloadExpiresHours: number;
  watermarkedPreview: boolean;
  previewMaxWidth: number;
  previewQuality: number;
  useCustomStripe: boolean;
  stripeAccountLabel?: string;
  stripeSecretKey?: string;
  stripeWebhookSecret?: string;
  customStripeConfigured?: boolean;
  customStripeWebhookConfigured?: boolean;
  termsText?: string;
  saleAlbumIds?: string[];
};
type Order = {
  _id: string;
  orderNo: string;
  email: string;
  amount: number;
  currency: string;
  status: string;
  imageIds?: unknown[];
  createdAt?: string;
  deliverySentAt?: string;
};
const normalIds = (value: unknown): string[] =>
  Array.isArray(value)
    ? value
        .map((item) =>
          typeof item === "string"
            ? item
            : (item as { _id?: string })?._id || "",
        )
        .filter(Boolean)
    : [];

export default function StoreManager() {
  const qc = useQueryClient();
  const eventsQ = useQueryWrapper<{ data: EventRow[] }>(
    ["store-events"],
    "/event/my-events?page=1&limit=100",
    { withToken: true, withCredentials: true },
  );
  const events = eventsQ.data?.data || [];
  const [eventId, setEventId] = useState("");
  const selected = eventId || events[0]?._id || "";
  const settingsQ = useQueryWrapper<{ data: StoreSettings }>(
    ["store-settings", selected],
    selected ? `/store/settings?eventId=${selected}` : "/store/settings",
    { withToken: true, withCredentials: true, enabled: Boolean(selected) },
  );
  const ordersQ = useQueryWrapper<{ data: Order[] }>(
    ["store-orders", selected],
    selected ? `/store/orders?eventId=${selected}&limit=100` : "/store/orders",
    {
      withToken: true,
      withCredentials: true,
      enabled: Boolean(selected),
      refetchInterval: 8000,
    },
  );
  const albumsQ = useQueryWrapper<{ data: Album[] }>(
    ["store-albums", selected],
    selected ? `/album/get-all?eventId=${selected}` : "/album/get-all",
    { withToken: true, withCredentials: true, enabled: Boolean(selected) },
  );
  const photosQ = useQueryWrapper<{ data: SalePhoto[] }>(
    ["store-sale-photos", selected],
    selected ? `/store/sale-photos?eventId=${selected}` : "/store/sale-photos",
    { withToken: true, withCredentials: true, enabled: Boolean(selected) },
  );
  const [form, setForm] = useState<StoreSettings>({
    enabled: false,
    currency: "USD",
    singlePhotoPrice: 5,
    bundlePrice: 0,
    bundleMinPhotos: 10,
    downloadExpiresHours: 72,
    watermarkedPreview: true,
    previewMaxWidth: 1200,
    previewQuality: 64,
    useCustomStripe: false,
    stripeSecretKey: "",
    stripeWebhookSecret: "",
    termsText: "",
    saleAlbumIds: [],
  });
  useEffect(() => {
    const data = settingsQ.data?.data;
    if (data)
      setForm({
        ...data,
        previewMaxWidth: data.previewMaxWidth || 1200,
        previewQuality: data.previewQuality || 64,
        useCustomStripe: Boolean(data.useCustomStripe),
        stripeSecretKey: "",
        stripeWebhookSecret: "",
        termsText: data.termsText || "",
        saleAlbumIds: normalIds(data.saleAlbumIds),
      });
  }, [settingsQ.data?.data]);
  const refresh = () => {
    qc.invalidateQueries({ queryKey: ["store-settings"] });
    qc.invalidateQueries({ queryKey: ["store-sale-photos"] });
    qc.invalidateQueries({ queryKey: ["store-orders"] });
  };
  const save = useMutation({
    mutationFn: async () => {
      const [r, e] = await PatchRequestAxios(
        "/store/settings",
        { eventId: selected, ...form },
        { withToken: true, withCredentials: true },
      );
      if (e || !r) throw new Error(e?.message || "Could not save store");
      return r;
    },
    onSuccess: () => {
      toast.success("Store settings saved");
      refresh();
    },
    onError: (e: Error) => toast.error(e.message),
  });
  const sale = useMutation({
    mutationFn: async ({ id, value }: { id: string; value: boolean }) => {
      const [r, e] = await PatchRequestAxios(
        "/store/sale-photos",
        { eventId: selected, imageIds: [id], isForSale: value },
        { withToken: true, withCredentials: true },
      );
      if (e || !r) throw new Error(e?.message || "Could not update photo");
      return r;
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ["store-sale-photos"] }),
    onError: (e: Error) => toast.error(e.message),
  });
  const toggleAlbum = (id: string) =>
    setForm((current) => {
      const ids = new Set(current.saleAlbumIds || []);
      ids.has(id) ? ids.delete(id) : ids.add(id);
      return { ...current, saleAlbumIds: [...ids] };
    });
  const paid = (ordersQ.data?.data || []).filter((o) => o.status === "paid");
  const revenue = paid.reduce((sum, o) => sum + Number(o.amount || 0), 0);
  const event = events.find((e) => e._id === selected);
  return (
    <PlannerLayout>
      <div className="space-y-5">
        <div className="flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
          <div>
            <p className="text-sm font-medium text-muted-foreground">
              Phase 3 monetization
            </p>
            <h1 className="text-2xl font-bold">Online Store</h1>
            <p className="mt-1 text-sm text-muted-foreground">
              Choose categories/photos to sell, collect payment, then deliver
              the purchased originals automatically.
            </p>
          </div>
          <div className="flex gap-2">
            <Select value={selected} onValueChange={setEventId}>
              <SelectTrigger className="w-64">
                <SelectValue placeholder="Select event" />
              </SelectTrigger>
              <SelectContent>
                {events.map((e) => (
                  <SelectItem key={e._id} value={e._id}>
                    {e.title}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            {selected ? (
              <Button variant="outline" asChild>
                <a
                  href={`/#/store/${selected}`}
                  target="_blank"
                  rel="noreferrer"
                >
                  <ExternalLink className="mr-2 h-4 w-4" />
                  Open store
                </a>
              </Button>
            ) : null}
          </div>
        </div>
        <div className="grid gap-3 sm:grid-cols-3">
          <Metric value={ordersQ.data?.data?.length || 0} label="Orders" />
          <Metric value={paid.length} label="Paid" />
          <Metric
            value={`${form.currency} ${revenue.toFixed(2)}`}
            label="Revenue"
          />
        </div>
        <Card className="overflow-hidden">
          <CardHeader className="border-b bg-muted/20">
            <div className="flex items-center gap-2">
              <ShoppingBag className="h-5 w-5" />
              <CardTitle>Automatic purchase delivery</CardTitle>
            </div>
          </CardHeader>
          <CardContent className="grid gap-3 p-5 md:grid-cols-3">
            <DeliveryStep
              icon={<ImageIcon className="h-5 w-5" />}
              title="1. Preview"
              text={form.watermarkedPreview ? "Low-resolution, watermarked previews protect the originals." : "Optimized previews are shown before purchase."}
            />
            <DeliveryStep
              icon={<CreditCard className="h-5 w-5" />}
              title="2. Purchase"
              text={form.useCustomStripe ? "Payment goes through this event's connected Stripe account." : "Payment goes through the platform Stripe checkout."}
            />
            <DeliveryStep
              icon={<Send className="h-5 w-5" />}
              title="3. Deliver"
              text="After payment, the full-resolution original is delivered without a watermark by secure link."
            />
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>{event?.title || "Store settings"}</CardTitle>
          </CardHeader>
          <CardContent className="grid gap-4 md:grid-cols-2">
            <Toggle
              label="Enable public store"
              checked={form.enabled}
              onChange={(v) => setForm((f) => ({ ...f, enabled: v }))}
            />
            <Toggle
              label="Watermarked preview"
              checked={form.watermarkedPreview}
              onChange={(v) =>
                setForm((f) => ({ ...f, watermarkedPreview: v }))
              }
            />
            <Field
              label="Currency"
              value={form.currency}
              onChange={(v) =>
                setForm((f) => ({ ...f, currency: v.toUpperCase() }))
              }
            />
            <Field
              label="Single photo price"
              type="number"
              value={String(form.singlePhotoPrice)}
              onChange={(v) =>
                setForm((f) => ({ ...f, singlePhotoPrice: Number(v) || 0 }))
              }
            />
            <Field
              label="Bundle price (0 disables bundle)"
              type="number"
              value={String(form.bundlePrice)}
              onChange={(v) =>
                setForm((f) => ({ ...f, bundlePrice: Number(v) || 0 }))
              }
            />
            <Field
              label="Bundle starts at photos"
              type="number"
              value={String(form.bundleMinPhotos)}
              onChange={(v) =>
                setForm((f) => ({ ...f, bundleMinPhotos: Number(v) || 2 }))
              }
            />
            <Field
              label="Download link hours"
              type="number"
              value={String(form.downloadExpiresHours)}
              onChange={(v) =>
                setForm((f) => ({
                  ...f,
                  downloadExpiresHours: Number(v) || 72,
                }))
              }
            />
            <Field
              label="Preview max width (px)"
              type="number"
              value={String(form.previewMaxWidth)}
              onChange={(v) =>
                setForm((f) => ({ ...f, previewMaxWidth: Number(v) || 1200 }))
              }
            />
            <Field
              label="Preview JPEG quality (30-90)"
              type="number"
              value={String(form.previewQuality)}
              onChange={(v) =>
                setForm((f) => ({ ...f, previewQuality: Number(v) || 64 }))
              }
            />
            <Field
              label="Store terms"
              value={form.termsText || ""}
              onChange={(v) => setForm((f) => ({ ...f, termsText: v }))}
            />
            <div className="md:col-span-2 rounded-xl border bg-muted/30 p-4 text-sm">
              <p className="font-semibold">Preview vs purchased file</p>
              <p className="mt-1 text-muted-foreground">
                Public store previews are resized and watermarked server-side.
                After payment, Airpix delivers the original full-resolution file
                without the watermark.
              </p>
              <Button
                variant="outline"
                size="sm"
                className="mt-3"
                onClick={() =>
                  selected &&
                  (window.location.hash = `#/planner/event/${selected}/experience`)
                }
              >
                Watermark position, opacity & size
              </Button>
            </div>
            <div className="md:col-span-2 space-y-3 rounded-xl border p-4">
              <Toggle
                label="Use my own Stripe account for this event"
                checked={form.useCustomStripe}
                onChange={(v) => setForm((f) => ({ ...f, useCustomStripe: v }))}
              />
              {form.useCustomStripe ? (
                <div className="grid gap-3 md:grid-cols-2">
                  <Field
                    label="Stripe account label"
                    value={form.stripeAccountLabel || ""}
                    onChange={(v) =>
                      setForm((f) => ({ ...f, stripeAccountLabel: v }))
                    }
                  />
                  <div className="space-y-2">
                    <Label>Stripe secret key</Label>
                    <Input
                      type="password"
                      value={form.stripeSecretKey || ""}
                      onChange={(e) =>
                        setForm((f) => ({
                          ...f,
                          stripeSecretKey: e.target.value,
                        }))
                      }
                      placeholder={
                        form.customStripeConfigured
                          ? "Saved - leave blank to keep it"
                          : "sk_live_... or sk_test_..."
                      }
                    />
                  </div>
                  <div className="space-y-2">
                    <Label>Stripe webhook signing secret</Label>
                    <Input
                      type="password"
                      value={form.stripeWebhookSecret || ""}
                      onChange={(e) =>
                        setForm((f) => ({
                          ...f,
                          stripeWebhookSecret: e.target.value,
                        }))
                      }
                      placeholder={
                        form.customStripeWebhookConfigured
                          ? "Saved - leave blank to keep it"
                          : "whsec_..."
                      }
                    />
                  </div>
                  <div className="rounded-xl bg-muted/40 p-3 text-xs text-muted-foreground">
                    <p className="font-medium text-foreground">
                      Webhook endpoint
                    </p>
                    <p className="mt-1 break-all">{`${import.meta.env.VITE_BASE_URL || window.location.origin}/store/stripe-webhook?eventId=${selected}`}</p>
                  </div>
                </div>
              ) : null}
            </div>
            <div className="md:col-span-2 space-y-2">
              <Label>Categories for sale</Label>
              <p className="text-xs text-muted-foreground">
                No category selected means all categories are eligible. Select
                categories to restrict sales.
              </p>
              <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
                {(albumsQ.data?.data || []).map((album) => (
                  <label
                    key={album._id}
                    className="flex items-center gap-2 rounded-xl border p-3 text-sm"
                  >
                    <Checkbox
                      checked={(form.saleAlbumIds || []).includes(album._id)}
                      onCheckedChange={() => toggleAlbum(album._id)}
                    />
                    {album.title}
                  </label>
                ))}
              </div>
            </div>
            <div className="md:col-span-2 flex justify-end">
              <Button
                disabled={!selected || save.isPending}
                onClick={() => save.mutate()}
              >
                {save.isPending ? (
                  <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                ) : (
                  <Save className="mr-2 h-4 w-4" />
                )}
                Save store
              </Button>
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardHeader>
            <CardTitle>Per-photo sale control</CardTitle>
          </CardHeader>
          <CardContent>
            {photosQ.isLoading ? (
              <Loader2 className="h-6 w-6 animate-spin" />
            ) : (photosQ.data?.data || []).length === 0 ? (
              <p className="text-sm text-muted-foreground">
                No published photos yet.
              </p>
            ) : (
              <div className="grid grid-cols-2 gap-3 md:grid-cols-3 lg:grid-cols-5">
                {(photosQ.data?.data || []).map((photo) => (
                  <div
                    key={photo._id}
                    className="overflow-hidden rounded-xl border"
                  >
                    <img
                      src={photo.imageUrl}
                      className="aspect-[4/3] w-full object-cover"
                      loading="lazy"
                    />
                    <div className="flex items-center justify-between gap-2 p-2">
                      <span className="truncate text-xs text-muted-foreground">
                        {typeof photo.albumId === "object"
                          ? photo.albumId?.title || "Photo"
                          : "Photo"}
                      </span>
                      <Switch
                        disabled={sale.isPending}
                        checked={photo.isForSale !== false}
                        onCheckedChange={(value) =>
                          sale.mutate({ id: photo._id, value })
                        }
                      />
                    </div>
                  </div>
                ))}
              </div>
            )}
          </CardContent>
        </Card>
        <Card>
          <CardHeader>
            <CardTitle>Recent orders</CardTitle>
          </CardHeader>
          <CardContent>
            {ordersQ.isLoading ? (
              <Loader2 className="h-6 w-6 animate-spin" />
            ) : (ordersQ.data?.data || []).length === 0 ? (
              <p className="text-sm text-muted-foreground">No orders yet.</p>
            ) : (
              <div className="space-y-2">
                {(ordersQ.data?.data || []).map((order) => (
                  <div
                    key={order._id}
                    className="grid gap-2 rounded-xl border p-3 md:grid-cols-[1fr_1fr_auto_auto] md:items-center"
                  >
                    <div>
                      <p className="font-medium">{order.orderNo}</p>
                      <p className="text-xs text-muted-foreground">
                        {order.email}
                      </p>
                    </div>
                    <p className="text-sm">
                      {order.imageIds?.length || 0} photos
                    </p>
                    <p className="font-semibold">
                      {order.currency} {Number(order.amount).toFixed(2)}
                    </p>
                    <Badge
                      variant={
                        order.status === "paid"
                          ? "default"
                          : order.status === "refunded"
                            ? "destructive"
                            : "outline"
                      }
                    >
                      {order.status}
                    </Badge>
                  </div>
                ))}
              </div>
            )}
          </CardContent>
        </Card>
      </div>
    </PlannerLayout>
  );
}
function DeliveryStep({
  icon,
  title,
  text,
}: {
  icon: ReactNode;
  title: string;
  text: string;
}) {
  return (
    <div className="rounded-2xl border bg-background p-4 transition-all duration-200 hover:-translate-y-0.5 hover:shadow-sm">
      <span className="mb-3 flex h-10 w-10 items-center justify-center rounded-xl bg-muted">
        {icon}
      </span>
      <p className="text-sm font-semibold">{title}</p>
      <p className="mt-1 text-xs leading-5 text-muted-foreground">{text}</p>
    </div>
  );
}

function Metric({ value, label }: { value: string | number; label: string }) {
  return (
    <Card>
      <CardContent className="p-4">
        <p className="text-2xl font-bold">{value}</p>
        <p className="text-xs text-muted-foreground">{label}</p>
      </CardContent>
    </Card>
  );
}
function Toggle({
  label,
  checked,
  onChange,
}: {
  label: string;
  checked: boolean;
  onChange: (v: boolean) => void;
}) {
  return (
    <div className="flex items-center justify-between rounded-xl border p-3">
      <span className="text-sm font-medium">{label}</span>
      <Switch checked={checked} onCheckedChange={onChange} />
    </div>
  );
}
function Field({
  label,
  value,
  onChange,
  type = "text",
}: {
  label: string;
  value: string;
  onChange: (v: string) => void;
  type?: string;
}) {
  return (
    <div className="space-y-2">
      <Label>{label}</Label>
      <Input
        type={type}
        value={value}
        onChange={(e) => onChange(e.target.value)}
      />
    </div>
  );
}
