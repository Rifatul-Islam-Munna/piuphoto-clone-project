import { useEffect, useMemo, useState } from "react";
import { useParams, useSearchParams } from "react-router-dom";
import { CheckCircle2, Download, Loader2, Mail, ShieldCheck } from "lucide-react";
import { GetRequestAxios, PostRequestAxios } from "@/api-hooks/api-hooks";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";

type PurchasedPhoto = {
  _id: string;
  previewUrl: string;
  downloadUrl: string;
};
type Order = {
  orderNo: string;
  email: string;
  currency: string;
  amount: number;
  downloadExpiresAt?: string;
  deliverySentAt?: string;
  eventId?: { _id?: string; title?: string };
  imageIds?: PurchasedPhoto[];
};

const baseUrl = import.meta.env.VITE_BASE_URL ?? "";

function apiHref(path: string): string {
  if (path.startsWith("https://") || path.startsWith("http://")) return path;
  return `${baseUrl}${path}`;
}

export default function StoreOrder() {
  const { orderId = "" } = useParams();
  const [params, setParams] = useSearchParams();
  const [token, setToken] = useState(params.get("token") || "");
  const [order, setOrder] = useState<Order>();
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState("");

  useEffect(() => {
    let cancelled = false;
    void (async () => {
      let access = token;
      const session = params.get("session_id");
      if (!access && session) {
        const [verified, error] = await PostRequestAxios<{ downloadToken?: string }>(
          "/store/public/verify",
          { orderId, sessionId: session },
          { withCredentials: false, redirectOnUnauthorized: false },
        );
        if (error || !verified?.downloadToken) {
          if (!cancelled) {
            setLoading(false);
            setLoadError(error?.message || "Payment verification failed.");
          }
          return;
        }
        access = verified.downloadToken;
        setToken(access);
        const next = new URLSearchParams();
        next.set("token", access);
        setParams(next, { replace: true });
      }
      if (!access) {
        if (!cancelled) {
          setLoading(false);
          setLoadError("Use the secure link from your purchase confirmation.");
        }
        return;
      }
      const [data, error] = await GetRequestAxios<{ data: Order }>(
        `/store/public/order?orderId=${encodeURIComponent(orderId)}&token=${encodeURIComponent(access)}`,
        { withCredentials: false, redirectOnUnauthorized: false },
      );
      if (!cancelled) {
        setLoading(false);
        if (error || !data?.data) {
          setLoadError(error?.message || "Order link is invalid or expired.");
        } else {
          setOrder(data.data);
          setLoadError("");
        }
      }
    })();
    return () => { cancelled = true; };
  }, [orderId, params, setParams, token]);

  const allUrl = useMemo(
    () =>
      apiHref(
        `/store/public/download-all.zip?orderId=${encodeURIComponent(orderId)}&token=${encodeURIComponent(token)}`,
      ),
    [orderId, token],
  );

  const trackDownload = (imageId?: string) => {
    if (!order?.eventId?._id) return;
    void PostRequestAxios(
      "/analytics/track",
      {
        eventId: order.eventId._id,
        ...(imageId ? { imageId } : {}),
        type: "download",
        channel: "store",
      },
      { withCredentials: false, redirectOnUnauthorized: false },
    );
  };

  if (loading) {
    return (
      <main className="flex min-h-screen items-center justify-center">
        <Loader2 className="h-8 w-8 animate-spin" aria-label="Verifying your payment" />
      </main>
    );
  }
  if (!order) {
    return (
      <main className="flex min-h-screen items-center justify-center px-5 text-center">
        <div className="max-w-md space-y-3">
          <h1 className="text-2xl font-bold">Order access unavailable</h1>
          <p className="text-sm text-muted-foreground">
            {loadError || "Please use the secure download link sent to your email."}
          </p>
          <Button variant="outline" onClick={() => { window.location.reload(); }}>
            Retry
          </Button>
        </div>
      </main>
    );
  }

  const photos = order.imageIds || [];
  const expiry = order.downloadExpiresAt
    ? new Date(order.downloadExpiresAt).toLocaleString()
    : "as stated in your confirmation";

  return (
    <main className="min-h-screen bg-[#f7f6f3] px-3 py-8 sm:px-6">
      <div className="mx-auto max-w-5xl space-y-6">
        <Card className="overflow-hidden rounded-2xl border-0 bg-white shadow-sm">
          <CardContent className="space-y-5 p-5 sm:p-8">
            <div className="flex items-center gap-2 text-sm font-semibold uppercase tracking-widest text-emerald-700">
              <CheckCircle2 className="h-5 w-5" />
              Payment confirmed
            </div>
            <div className="space-y-2">
              <p className="text-xs uppercase tracking-widest text-muted-foreground">{order.orderNo}</p>
              <h1 className="text-2xl font-bold tracking-tight sm:text-4xl">
                Your photos are ready
              </h1>
              <p className="text-sm text-muted-foreground">
                {photos.length} full-resolution original{photos.length === 1 ? "" : "s"} from{" "}
                {order.eventId?.title || "your event"} · Paid {order.currency}{" "}
                {Number(order.amount).toFixed(2)}
              </p>
            </div>

            <div className="flex flex-col gap-3 sm:flex-row">
              <Button asChild size="lg" className="w-full sm:w-auto">
                <a
                  href={allUrl}
                  referrerPolicy="no-referrer"
                  onClick={() => trackDownload()}
                >
                  <Download className="mr-2 h-5 w-5" />
                  Download all originals (ZIP)
                </a>
              </Button>
              <Button
                size="lg"
                variant="outline"
                className="w-full sm:w-auto"
                onClick={() =>
                  document.getElementById("purchased-photos")?.scrollIntoView({ behavior: "smooth" })
                }
              >
                Save photos individually
              </Button>
            </div>
            <p className="text-xs text-muted-foreground">
              One tap starts a browser download. On iPhone, find your ZIP in
              Files &gt; Downloads. You can also save photos one by one below.
            </p>

            <div className="flex items-start gap-3 rounded-xl bg-[#f6f3ed] p-4">
              <Mail className="mt-0.5 h-5 w-5 shrink-0 text-[#b3560e]" />
              <div className="space-y-1 text-sm">
                <p className="font-semibold">Secure download link by email</p>
                <p className="text-muted-foreground">
                  The secure link is sent to <strong>{order.email}</strong> when
                  SMTP is configured. You can download all your photos here now,
                  even if the email is delayed or unavailable.
                </p>
              </div>
            </div>
            <p className="flex items-center gap-2 text-xs text-muted-foreground">
              <ShieldCheck className="h-4 w-4" />
              Private purchase link · Download access expires {expiry}
            </p>
          </CardContent>
        </Card>

        <section id="purchased-photos" className="space-y-4">
          <div>
            <h2 className="text-xl font-bold">Your purchased photos</h2>
            <p className="text-sm text-muted-foreground">
              Download each original separately if you prefer not to save a large ZIP.
            </p>
          </div>
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4">
            {photos.map((image, index) => (
              <Card key={image._id} className="overflow-hidden rounded-xl bg-white py-0">
                <img
                  src={apiHref(image.previewUrl)}
                  alt={`Purchased photo ${index + 1}`}
                  loading="lazy"
                  decoding="async"
                  className="aspect-[4/3] w-full bg-muted object-contain"
                />
                <CardContent className="p-2.5">
                  <Button asChild variant="outline" size="sm" className="w-full">
                    <a
                      href={apiHref(image.downloadUrl)}
                      referrerPolicy="no-referrer"
                      onClick={() => trackDownload(image._id)}
                      aria-label={`Download purchased photo ${index + 1}`}
                    >
                      <Download className="mr-1.5 h-4 w-4" />
                      Save original
                    </a>
                  </Button>
                </CardContent>
              </Card>
            ))}
          </div>
        </section>
      </div>
    </main>
  );
}
