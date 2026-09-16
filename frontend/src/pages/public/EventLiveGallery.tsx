import {
  type ChangeEvent,
  type CSSProperties,
  type ReactNode,
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import { Link, useParams, useSearchParams } from "react-router-dom";
import {
  ArrowLeft,
  Camera,
  Check,
  CheckCircle2,
  ChevronLeft,
  ChevronDown,
  ChevronRight,
  Copy,
  Download,
  Folder,
  Image as ImageIcon,
  Images,
  Loader2,
  Lock,
  Mail,
  Maximize2,
  MoreHorizontal,
  Pause,
  Play,
  RefreshCw,
  Search,
  Share2,
  ShieldCheck,
  ShoppingCart,
  Trash2,
  Upload,
  UserRoundSearch,
  X,
} from "lucide-react";
import QRCode from "qrcode";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Checkbox } from "@/components/ui/checkbox";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Separator } from "@/components/ui/separator";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
} from "@/components/ui/sheet";
import {
  GetRequestAxios,
  PatchRequestAxios,
  PostRequestAxios,
} from "@/api-hooks/api-hooks";

type Branding = {
  logoUrl?: string;
  coverUrl?: string;
  coverText?: string;
  watermarkUrl?: string;
  watermarkPosition?: string;
  watermarkOpacity?: number;
  watermarkScale?: number;
  primaryColor?: string;
  accentColor?: string;
  fontFamily?: string;
  footerText?: string;
  sponsorText?: string;
  whiteLabel?: boolean;
};

type GalleryInfo = {
  title: string;
  description?: string;
  image?: { url?: string };
  visibility: "public" | "private" | "password" | "facial";
  unlocked: boolean;
  requiresPassword: boolean;
  requiresPrivateLink: boolean;
  requiresFaceSearch: boolean;
  faceSearchEnabled: boolean;
  faceConsentRequired: boolean;
  guestNotificationsEnabled: boolean;
  emailNotificationsEnabled?: boolean;
  whatsappNotificationsEnabled?: boolean;
  facialPrivacyMode?: "off" | "hide_non_matches" | "blur_non_matches";
  branding?: Branding;
};

type GalleryImage = {
  _id?: string;
  id?: string;
  imageUrl?: string;
  isEnhanced?: boolean;
  mediaType?: "photo" | "video";
  userTakenBy?: { name?: string } | string;
  purchaseRequired?: boolean;
  storeImageId?: string;
};

type GalleryImageResponse = {
  data?: GalleryImage[];
  totalItems?: number;
  storeEnabled?: boolean;
};

type Album = {
  _id?: string;
  id?: string;
  title?: string;
  imagesCount?: number;
};

type PersonalGalleryResponse = GalleryImageResponse & {
  event?: { branding?: Branding };
  notificationPreferences?: {
    email?: string;
    whatsapp?: string;
    notifyEmail?: boolean;
    notifyWhatsapp?: boolean;
  };
};

type StoreCatalog = {
  settings: {
    currency: string;
    singlePhotoPrice: number;
    wholeEventPrice: number;
    bundlePrice: number;
    bundleMinPhotos: number;
    termsText?: string;
  };
  data: Array<{ _id: string }>;
  totalItems: number;
};

type PurchaseMode = "selected" | "event";

const pageSize = 24;
const imageAccept = "image/jpeg,image/png,image/webp";
const baseUrl = import.meta.env.VITE_BASE_URL ?? "";
const imageId = (image: GalleryImage) =>
  image._id || image.id || image.imageUrl || "";
const assetUrl = (url?: string) => {
  if (!url) return "";
  return /^https?:\/\//i.test(url) ? url : `${baseUrl}${url}`;
};
const publicImageUrl = (eventId: string, id: string) =>
  `${window.location.origin}${window.location.pathname}#/event/${eventId}/image/${id}`;

type ShareNetwork = "facebook" | "x" | "pinterest" | "whatsapp" | "email";

const socialShareUrl = (network: ShareNetwork, url: string, title: string) => {
  const link = encodeURIComponent(url);
  const text = encodeURIComponent(title);
  switch (network) {
    case "facebook":
      return `https://www.facebook.com/sharer/sharer.php?u=${link}`;
    case "x":
      return `https://twitter.com/intent/tweet?url=${link}&text=${text}`;
    case "pinterest":
      return `https://pinterest.com/pin/create/button/?url=${link}&description=${text}`;
    case "whatsapp":
      return `https://wa.me/?text=${encodeURIComponent(`${title} ${url}`)}`;
    default:
      return `mailto:?subject=${text}&body=${link}`;
  }
};

const watermarkPositionClass = (position?: string) => {
  switch (position) {
    case "top_left":
      return "left-3 top-3";
    case "top_center":
      return "left-1/2 top-3 -translate-x-1/2";
    case "top_right":
      return "right-3 top-3";
    case "center_left":
      return "left-3 top-1/2 -translate-y-1/2";
    case "center":
      return "left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2";
    case "center_right":
      return "right-3 top-1/2 -translate-y-1/2";
    case "bottom_left":
      return "bottom-3 left-3";
    case "bottom_center":
      return "bottom-3 left-1/2 -translate-x-1/2";
    default:
      return "bottom-3 right-3";
  }
};

async function downloadImage(url: string, filename: string) {
  try {
    const response = await fetch(url, { mode: "cors" });
    if (!response.ok) throw new Error("download failed");
    const blob = await response.blob();
    const localUrl = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = localUrl;
    link.download = filename;
    link.click();
    URL.revokeObjectURL(localUrl);
  } catch {
    window.open(url, "_blank", "noopener,noreferrer");
  }
}

export default function EventLiveGallery() {
  const { eventId = "", albumId, imageId: routeImageId } = useParams();
  const [params, setParams] = useSearchParams();
  const faceEnrollment = params.get("face") === "1";
  const faceInput = useRef<HTMLInputElement>(null);
  const faceUploadInput = useRef<HTMLInputElement>(null);
  const registerInput = useRef<HTMLInputElement>(null);
  const storageKey = `gallery_access_${eventId}_${albumId || "all"}`;
  const guestStorageKey = `personal_gallery_${eventId}_${albumId || "all"}`;

  const [accessToken, setAccessToken] = useState(
    params.get("access") || localStorage.getItem(storageKey) || "",
  );
  const [guestToken, setGuestToken] = useState(
    params.get("guest") || localStorage.getItem(guestStorageKey) || "",
  );
  const [info, setInfo] = useState<GalleryInfo>();
  const [images, setImages] = useState<GalleryImage[]>([]);
  const [albums, setAlbums] = useState<Album[]>([]);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [visibleCount, setVisibleCount] = useState(pageSize);
  const [loading, setLoading] = useState(true);
  const [password, setPassword] = useState("");
  const [unlocking, setUnlocking] = useState(false);
  const [faceSearching, setFaceSearching] = useState(false);
  const [faceMatches, setFaceMatches] = useState(false);
  const [downloading, setDownloading] = useState(false);
  const [selfies, setSelfies] = useState<File[]>([]);
  const [registering, setRegistering] = useState(false);
  const [email, setEmail] = useState("");
  const [whatsapp, setWhatsapp] = useState("");
  const [notifyEmail, setNotifyEmail] = useState(true);
  const [notifyWhatsapp, setNotifyWhatsapp] = useState(faceEnrollment);
  const [consent, setConsent] = useState(false);
  const [blurredIds, setBlurredIds] = useState<string[]>([]);
  const [savingPreferences, setSavingPreferences] = useState(false);
  const [storeEnabled, setStoreEnabled] = useState(false);
  const [storeCatalog, setStoreCatalog] = useState<StoreCatalog>();
  const [purchaseOpen, setPurchaseOpen] = useState(false);
  const [purchaseMode, setPurchaseMode] = useState<PurchaseMode>("selected");
  const [purchaseIds, setPurchaseIds] = useState<Set<string>>(new Set());
  const [checkingOut, setCheckingOut] = useState(false);
  const [checkoutKey, setCheckoutKey] = useState("");
  const [focusedIndex, setFocusedIndex] = useState(-1);
  const [slideshow, setSlideshow] = useState(false);
  const [findMeOpen, setFindMeOpen] = useState(false);
  const [shareOpen, setShareOpen] = useState(false);
  const [shareUrl, setShareUrl] = useState("");
  const [shareTitle, setShareTitle] = useState("");
  const [shareQr, setShareQr] = useState("");

  const commonParams = useCallback(
    (includeAccess = true) => {
      const query = new URLSearchParams({ eventId });
      if (albumId) query.set("albumId", albumId);
      if (includeAccess && accessToken) query.set("accessToken", accessToken);
      return query;
    },
    [accessToken, albumId, eventId],
  );

  const track = useCallback(
    (type: string, targetImageId?: string) => {
      if (!eventId) return;
      void PostRequestAxios(
        "/analytics/track",
        {
          eventId,
          type,
          ...(albumId ? { albumId } : {}),
          ...(targetImageId ? { imageId: targetImageId } : {}),
          channel: guestToken ? "personal_gallery" : "live_gallery",
        },
        { withCredentials: false, redirectOnUnauthorized: false },
      );
    },
    [albumId, eventId, guestToken],
  );

  useEffect(() => {
    if (eventId) track("gallery_visit");
  }, [eventId, track]);
  const loadInfo = useCallback(async () => {
    if (!eventId) return undefined;
    const [data, error] = await GetRequestAxios<GalleryInfo>(
      `/gallery-access/info?${commonParams().toString()}`,
      { withCredentials: false, redirectOnUnauthorized: false },
    );
    if (error || !data) {
      toast.error(error?.message || "Gallery unavailable");
      return undefined;
    }
    setInfo(data);
    return data;
  }, [commonParams, eventId]);

  const loadPublic = useCallback(async () => {
    if (!eventId) return;
    const [data, error] = await GetRequestAxios<GalleryImageResponse>(
      `/eventImage/public?${commonParams().toString()}`,
      { withCredentials: false, redirectOnUnauthorized: false },
    );
    if (!error) {
      setImages(data?.data || []);
      setStoreEnabled(Boolean(data?.storeEnabled));
      setFaceMatches(false);
    }
    if (!albumId) {
      const albumQuery = new URLSearchParams({ eventId });
      if (accessToken) albumQuery.set("accessToken", accessToken);
      const [albumData] = await GetRequestAxios<{ data?: Album[] }>(
        `/album/public?${albumQuery.toString()}`,
        { withCredentials: false, redirectOnUnauthorized: false },
      );
      setAlbums(albumData?.data || []);
    }
  }, [accessToken, albumId, commonParams, eventId]);

  const loadPersonal = useCallback(async () => {
    if (!guestToken || !eventId) return;
    const query = commonParams(false);
    query.set("guestToken", guestToken);
    const [data, error] = await GetRequestAxios<PersonalGalleryResponse>(
      `/guest-gallery/personal?${query.toString()}`,
      { withCredentials: false, redirectOnUnauthorized: false },
    );
    if (error || !data) {
      if (error?.statusCode === 401) {
        localStorage.removeItem(guestStorageKey);
        setGuestToken("");
      }
      return;
    }
    setImages(data.data || []);
    setStoreEnabled(Boolean(data.storeEnabled));
    setFaceMatches(true);
    if (data.notificationPreferences) {
      setEmail(data.notificationPreferences.email || "");
      setWhatsapp(data.notificationPreferences.whatsapp || "");
      setNotifyEmail(Boolean(data.notificationPreferences.notifyEmail));
      setNotifyWhatsapp(Boolean(data.notificationPreferences.notifyWhatsapp));
    }
  }, [commonParams, eventId, guestStorageKey, guestToken]);

  useEffect(() => {
    let mounted = true;
    void (async () => {
      setLoading(true);
      const galleryInfo = await loadInfo();
      if (!mounted || !galleryInfo) {
        if (mounted) setLoading(false);
        return;
      }
      if (guestToken) await loadPersonal();
      else if (galleryInfo.unlocked) await loadPublic();
      if (mounted) setLoading(false);
    })();
    return () => {
      mounted = false;
    };
  }, [guestToken, loadInfo, loadPersonal, loadPublic]);

  useEffect(() => {
    if (!eventId || !storeEnabled) {
      setStoreCatalog(undefined);
      return;
    }
    let cancelled = false;
    void GetRequestAxios<StoreCatalog>(
      `/store/public/catalog?eventId=${eventId}`,
      { withCredentials: false, redirectOnUnauthorized: false },
    ).then(([catalog, error]) => {
      if (!cancelled && !error && catalog) setStoreCatalog(catalog);
    });
    return () => {
      cancelled = true;
    };
  }, [eventId, storeEnabled]);

  useEffect(() => {
    setCheckoutKey("");
  }, [email, purchaseIds, purchaseMode, whatsapp]);

  useEffect(() => {
    if (!eventId || guestToken || !info?.unlocked) return;
    const source = new EventSource(
      `${baseUrl}/eventImage/public/stream?${commonParams().toString()}`,
    );
    const sync = () => void loadPublic();
    source.addEventListener("gallery", sync);
    const fallback = window.setInterval(sync, 15000);
    return () => {
      source.close();
      window.clearInterval(fallback);
    };
  }, [commonParams, eventId, guestToken, info?.unlocked, loadPublic]);

  useEffect(() => {
    if (!guestToken) return;
    const timer = window.setInterval(() => void loadPersonal(), 6000);
    return () => window.clearInterval(timer);
  }, [guestToken, loadPersonal]);

  useEffect(() => {
    if (
      !eventId ||
      guestToken ||
      info?.visibility !== "facial" ||
      info?.facialPrivacyMode !== "blur_non_matches"
    ) {
      setBlurredIds([]);
      return;
    }
    const query = new URLSearchParams({ eventId });
    if (albumId) query.set("albumId", albumId);
    void GetRequestAxios<{ data?: Array<{ _id: string }> }>(
      `/eventImage/public/blur-list?${query.toString()}`,
      { withCredentials: false, redirectOnUnauthorized: false },
    ).then(([data]) =>
      setBlurredIds((data?.data || []).map((item) => item._id)),
    );
  }, [albumId, eventId, guestToken, info?.facialPrivacyMode, info?.visibility]);

  useEffect(() => {
    const onScroll = () => {
      if (
        window.innerHeight + window.scrollY >=
        document.body.offsetHeight - 500
      ) {
        setVisibleCount((count) => Math.min(count + pageSize, images.length));
      }
    };
    window.addEventListener("scroll", onScroll);
    return () => window.removeEventListener("scroll", onScroll);
  }, [images.length]);

  useEffect(() => {
    if (!routeImageId || !images.length) return;
    const index = images.findIndex((image) => imageId(image) === routeImageId);
    if (index >= 0) setFocusedIndex(index);
  }, [images, routeImageId]);

  useEffect(() => {
    if (focusedIndex < 0) return;
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        setFocusedIndex(-1);
        setSlideshow(false);
      }
      if (images.length && event.key === "ArrowLeft") {
        setFocusedIndex((index) => (index - 1 + images.length) % images.length);
      }
      if (images.length && event.key === "ArrowRight") {
        setFocusedIndex((index) => (index + 1) % images.length);
      }
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [focusedIndex, images.length]);

  useEffect(() => {
    if (!slideshow || focusedIndex < 0 || images.length < 2) return;
    const timer = window.setInterval(() => {
      setFocusedIndex((index) => (index + 1) % images.length);
    }, 3500);
    return () => window.clearInterval(timer);
  }, [focusedIndex, images.length, slideshow]);

  const updateUrlToken = (key: "access" | "guest", value: string) => {
    const next = new URLSearchParams(params);
    if (value) next.set(key, value);
    else next.delete(key);
    setParams(next, { replace: true });
  };

  const unlock = async () => {
    if (!password.trim()) return;
    setUnlocking(true);
    const [data, error] = await PostRequestAxios<{ accessToken?: string }>(
      "/gallery-access/unlock",
      { eventId, ...(albumId ? { albumId } : {}), password: password.trim() },
      { withCredentials: false, redirectOnUnauthorized: false },
    );
    setUnlocking(false);
    if (error || !data?.accessToken) {
      toast.error(error?.message || "Wrong password");
      return;
    }
    localStorage.setItem(storageKey, data.accessToken);
    setAccessToken(data.accessToken);
    updateUrlToken("access", data.accessToken);
    setPassword("");
  };

  const registerPersonalGallery = async () => {
    const minimumSelfies = faceEnrollment ? 2 : 1;
    if (selfies.length < minimumSelfies || !consent) {
      toast.error(
        `Add at least ${minimumSelfies} selfie${minimumSelfies > 1 ? "s" : ""} and accept face-search consent`,
      );
      return;
    }
    if (faceEnrollment && (!email.trim() || !whatsapp.trim())) {
      toast.error("Email and WhatsApp are required for global face delivery");
      return;
    }
    setRegistering(true);
    const body = new FormData();
    selfies.slice(0, 5).forEach((file) => body.append("selfies", file));
    body.append("eventId", eventId);
    if (albumId) body.append("albumId", albumId);
    body.append("consent", "true");
    body.append("globalProfile", String(faceEnrollment));
    body.append("notifyEmail", String(notifyEmail));
    body.append("notifyWhatsapp", String(notifyWhatsapp));
    if (email.trim()) body.append("email", email.trim());
    if (whatsapp.trim()) body.append("whatsapp", whatsapp.trim());
    if (accessToken) body.append("accessToken", accessToken);
    const [data, error] = await PostRequestAxios<{
      guestToken?: string;
      updatedGlobalProfile?: boolean;
    }>("/guest-gallery/register", body, {
      withCredentials: false,
      redirectOnUnauthorized: false,
      headers: { "Content-Type": "multipart/form-data" },
    });
    setRegistering(false);
    if (error || !data?.guestToken) {
      toast.error(error?.message || "Could not create personal gallery");
      return;
    }
    localStorage.setItem(guestStorageKey, data.guestToken);
    setGuestToken(data.guestToken);
    updateUrlToken("guest", data.guestToken);
    toast.success(
      data.updatedGlobalProfile
        ? "Your global face profile was updated with the new selfies."
        : faceEnrollment
          ? "Global face profile created. Matching photos from enabled events can now reach you automatically."
          : "Personal gallery created. New matches will appear automatically.",
    );
  };

  const deletePersonalGallery = async () => {
    if (!guestToken) return;
    const [, error] = await PostRequestAxios(
      "/guest-gallery/delete",
      { eventId, guestToken },
      { withCredentials: false, redirectOnUnauthorized: false },
    );
    if (error) {
      toast.error(error.message);
      return;
    }
    localStorage.removeItem(guestStorageKey);
    setGuestToken("");
    setImages([]);
    updateUrlToken("guest", "");
    toast.success("Selfie profile removed");
  };

  const saveGuestPreferences = async () => {
    if (!guestToken) return;
    setSavingPreferences(true);
    const [, error] = await PatchRequestAxios(
      "/guest-gallery/preferences",
      {
        eventId,
        guestToken,
        ...(email.trim() ? { email: email.trim() } : {}),
        ...(whatsapp.trim() ? { whatsapp: whatsapp.trim() } : {}),
        notifyEmail,
        notifyWhatsapp,
      },
      { withCredentials: false, redirectOnUnauthorized: false },
    );
    setSavingPreferences(false);
    if (error) toast.error(error.message);
    else toast.success("Notification preferences saved");
  };

  const runFaceSearch = async (event: ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    event.target.value = "";
    if (!file) return;
    setFaceSearching(true);
    const body = new FormData();
    body.append("image", file);
    const query = commonParams();
    query.set("limit", "10000");
    const [data, error] = await PostRequestAxios<GalleryImageResponse>(
      `/eventImage/public/my-picture?${query.toString()}`,
      body,
      {
        withCredentials: false,
        redirectOnUnauthorized: false,
        headers: { "Content-Type": "multipart/form-data" },
      },
    );
    setFaceSearching(false);
    if (error) {
      toast.error(error.message || "Face search failed");
      return;
    }
    setImages(data?.data || []);
    setStoreEnabled(Boolean(data?.storeEnabled));
    setFaceMatches(true);
    track("face_search");
  };

  const toggle = (id: string) => {
    setSelected((current) => {
      const next = new Set(current);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  const availableStoreIds = useMemo(
    () => new Set((storeCatalog?.data || []).map((photo) => photo._id)),
    [storeCatalog],
  );

  const purchasePrice = useMemo(() => {
    if (!storeCatalog) return 0;
    if (purchaseMode === "event") {
      return Number(storeCatalog.settings.wholeEventPrice || 0);
    }
    const count = purchaseIds.size;
    return storeCatalog.settings.bundlePrice > 0 &&
      count >= storeCatalog.settings.bundleMinPhotos
      ? storeCatalog.settings.bundlePrice
      : storeCatalog.settings.singlePhotoPrice * count;
  }, [purchaseIds, purchaseMode, storeCatalog]);

  const buyAllPrice = useMemo(() => {
    if (!storeCatalog) return 0;
    if (storeCatalog.settings.wholeEventPrice > 0) {
      return storeCatalog.settings.wholeEventPrice;
    }
    const count = storeCatalog.data.length;
    return storeCatalog.settings.bundlePrice > 0 &&
      count >= storeCatalog.settings.bundleMinPhotos
      ? storeCatalog.settings.bundlePrice
      : storeCatalog.settings.singlePhotoPrice * count;
  }, [storeCatalog]);

  const openPurchase = useCallback(
    (ids: string[] = [], mode: PurchaseMode = "selected") => {
      if (!storeCatalog) {
        toast.error("Store details are still loading. Please try again.");
        return;
      }
      if (mode === "event") {
        if (storeCatalog.settings.wholeEventPrice <= 0) {
          toast.error("Buy all is not enabled for this event");
          return;
        }
        setPurchaseMode("event");
        setPurchaseIds(new Set(storeCatalog.data.map((photo) => photo._id)));
      } else {
        const eligible = [...new Set(ids)].filter((id) =>
          availableStoreIds.has(id),
        );
        if (!eligible.length) {
          toast.error("This photo is not available for purchase");
          return;
        }
        setPurchaseMode("selected");
        setPurchaseIds(new Set(eligible));
      }
      setCheckoutKey("");
      setPurchaseOpen(true);
      track("store_click");
    },
    [availableStoreIds, storeCatalog, track],
  );

  const buySelectedOrAll = () => {
    const selectedStoreIds = images
      .filter((image) => selected.has(imageId(image)) && image.purchaseRequired)
      .map((image) => image.storeImageId || imageId(image));
    if (selectedStoreIds.length) {
      openPurchase(selectedStoreIds);
    } else if ((storeCatalog?.settings.wholeEventPrice || 0) > 0) {
      openPurchase([], "event");
    } else {
      openPurchase(storeCatalog?.data.map((photo) => photo._id) || []);
    }
  };

  const startCheckout = async () => {
    if (!storeCatalog || !email.trim()) {
      toast.error("Enter the email where your originals should be delivered");
      return;
    }
    if (purchaseMode === "selected" && !purchaseIds.size) return;
    const idempotencyKey = checkoutKey || crypto.randomUUID();
    if (!checkoutKey) setCheckoutKey(idempotencyKey);
    setCheckingOut(true);
    const [data, error] = await PostRequestAxios<{ url?: string }>(
      "/store/public/checkout",
      {
        eventId,
        purchaseMode,
        imageIds: purchaseMode === "selected" ? [...purchaseIds] : undefined,
        email: email.trim(),
        whatsapp: whatsapp.trim() || undefined,
        idempotencyKey,
      },
      { withCredentials: false, redirectOnUnauthorized: false },
    );
    setCheckingOut(false);
    if (error || !data?.url) {
      toast.error(error?.message || "Checkout failed");
      return;
    }
    track("store_checkout");
    window.location.href = data.url;
  };

  const download = async (targetOverride?: GalleryImage[]) => {
    const target =
      targetOverride ||
      (selected.size
        ? images.filter((image) => selected.has(imageId(image)))
        : images);
    const paidIds = [
      ...new Set(
        target
          .filter((image) => image.purchaseRequired)
          .map((image) => image.storeImageId || imageId(image))
          .filter(Boolean),
      ),
    ];
    if (paidIds.length) {
      openPurchase(paidIds);
      return;
    }

    setDownloading(true);
    for (const [index, image] of target.entries()) {
      if (image.imageUrl) {
        track("download", imageId(image));
        await downloadImage(
          assetUrl(image.imageUrl),
          `event-photo-${imageId(image).slice(-8) || index + 1}.${image.mediaType === "video" ? "mp4" : "jpg"}`,
        );
      }
    }
    setDownloading(false);
  };

  const focusedImage =
    focusedIndex >= 0 && focusedIndex < images.length
      ? images[focusedIndex]
      : undefined;
  const shareGallery = async (targetImage?: GalleryImage) => {
    const targetId = targetImage ? imageId(targetImage) : undefined;
    const url = targetId
      ? publicImageUrl(eventId, targetId)
      : `${window.location.origin}${window.location.pathname}#/event/${eventId}`;
    const title = info?.title || "Event gallery";
    setShareUrl(url);
    setShareTitle(targetId ? "View this event photo" : "View this event gallery");
    try {
      const dataUrl = await QRCode.toDataURL(url, { width: 512, margin: 1 });
      setShareQr(dataUrl);
    } catch {
      setShareQr("");
    }
    setShareOpen(true);
    track("share", targetId);
  };

  const toggleFullscreen = async () => {
    if (document.fullscreenElement) await document.exitFullscreen();
    else await document.documentElement.requestFullscreen();
  };

  const startSlideshow = () => {
    if (!images.length) return;
    setFocusedIndex((current) => (current >= 0 ? current : 0));
    setSlideshow(true);
  };

  useEffect(() => {
    const legacyBuy = params.get("buy");
    if (!legacyBuy || !storeCatalog) return;
    if (legacyBuy === "all") openPurchase([], "event");
    else openPurchase(legacyBuy.split(",").filter(Boolean));
    const next = new URLSearchParams(params);
    next.delete("buy");
    setParams(next, { replace: true });
  }, [openPurchase, params, setParams, storeCatalog]);

  const closeFocusedImage = () => {
    setFocusedIndex(-1);
    setSlideshow(false);
    if (routeImageId) {
      const query = params.toString();
      window.location.hash = `/event/${eventId}${query ? `?${query}` : ""}`;
    }
  };

  const branding = info?.branding || {};
  const cover = branding.coverUrl || info?.image?.url;
  const style = {
    fontFamily: branding.fontFamily || undefined,
  } as CSSProperties;

  if (loading && !info) {
    return (
      <div className="flex min-h-screen flex-col items-center justify-center gap-3 bg-background">
        <div className="flex h-14 w-14 items-center justify-center rounded-2xl bg-primary/10">
          <Camera className="h-7 w-7 text-primary" />
        </div>
        <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
      </div>
    );
  }

  if (info?.requiresPassword && !info.unlocked && !guestToken) {
    return (
      <AccessShell info={info} branding={branding} cover={cover} style={style}>
        <Lock className="mb-4 h-9 w-9" />
        <h2 className="text-2xl font-bold">Password protected gallery</h2>
        <p className="mt-2 text-sm text-muted-foreground">
          Only guests with the event password can view or download these photos.
        </p>
        <div className="mt-5 flex gap-2">
          <Input
            type="password"
            value={password}
            onChange={(event) => setPassword(event.target.value)}
            onKeyDown={(event) => event.key === "Enter" && void unlock()}
            placeholder="Gallery password"
          />
          <Button
            disabled={unlocking || !password.trim()}
            onClick={() => void unlock()}
          >
            {unlocking ? (
              <Loader2 className="h-4 w-4 animate-spin" />
            ) : (
              "Unlock"
            )}
          </Button>
        </div>
      </AccessShell>
    );
  }

  if (info?.requiresPrivateLink && !info.unlocked && !guestToken) {
    return (
      <AccessShell info={info} branding={branding} cover={cover} style={style}>
        <div className="text-center">
          <ShieldCheck className="mx-auto mb-4 h-10 w-10" />
          <h2 className="text-2xl font-bold">Private gallery</h2>
          <p className="mt-2 text-sm text-muted-foreground">
            Ask the event organizer for a secure gallery link.
          </p>
        </div>
      </AccessShell>
    );
  }

  if (
    (faceEnrollment ||
      info?.requiresFaceSearch ||
      info?.visibility === "facial") &&
    !guestToken
  ) {
    return (
      <AccessShell info={info} branding={branding} cover={cover} style={style}>
        <UserRoundSearch className="mb-4 h-10 w-10" />
        <h2 className="text-2xl font-bold">
          {faceEnrollment
            ? "Create or update your global face profile"
            : "Find only your photos"}
        </h2>
        <p className="mt-2 text-sm text-muted-foreground">
          {faceEnrollment
            ? "Take 2-5 clear selfies and add your email + WhatsApp. We reuse the private face profile at enabled events so new matching photos can reach you automatically."
            : "Take or upload a selfie. Your personal gallery updates while photographers keep shooting."}
        </p>
        {faceEnrollment ? (
          <div className="mt-5 grid grid-cols-3 gap-2">
            <EnrollmentStep
              number="1"
              label="Selfies"
              done={selfies.length >= 2}
            />
            <EnrollmentStep
              number="2"
              label="Contact"
              done={Boolean(email.trim() && whatsapp.trim())}
            />
            <EnrollmentStep number="3" label="Consent" done={consent} />
          </div>
        ) : null}
        {info?.facialPrivacyMode === "blur_non_matches" && blurredIds.length ? (
          <div className="mt-4">
            <p className="mb-2 text-xs font-medium text-muted-foreground">
              Live gallery preview — photos stay blurred until they match you.
            </p>
            <div className="grid grid-cols-3 gap-2">
              {blurredIds.slice(0, 6).map((id) => (
                <img
                  key={id}
                  src={
                    baseUrl +
                    "/eventImage/public/blurred?id=" +
                    encodeURIComponent(id) +
                    "&eventId=" +
                    encodeURIComponent(eventId) +
                    (albumId ? "&albumId=" + encodeURIComponent(albumId) : "")
                  }
                  alt="Private blurred preview"
                  className="aspect-square w-full rounded-lg object-cover"
                />
              ))}
            </div>
          </div>
        ) : null}
        <div className="mt-5 space-y-4">
          <input
            ref={registerInput}
            type="file"
            accept={imageAccept}
            capture="user"
            multiple
            className="hidden"
            onChange={(event) => {
              const incoming = Array.from(event.target.files || []);
              setSelfies((current) => [...current, ...incoming].slice(0, 5));
              event.currentTarget.value = "";
            }}
          />
          <Button
            className="w-full"
            variant={selfies.length ? "outline" : "default"}
            disabled={selfies.length >= 5}
            onClick={() => registerInput.current?.click()}
          >
            <Camera className="mr-2 h-4 w-4" />
            {selfies.length
              ? `Add another selfie (${selfies.length}/5)`
              : faceEnrollment
                ? "Take your first selfie"
                : "Take or upload selfie"}
          </Button>
          {faceEnrollment ? (
            <div className="rounded-xl border bg-muted/20 p-3">
              <div className="flex items-center justify-between text-xs">
                <span className="font-medium">Face samples</span>
                <span className="text-muted-foreground">
                  {selfies.length}/5 · minimum 2
                </span>
              </div>
              <div className="mt-2 h-1.5 overflow-hidden rounded-full bg-muted">
                <div
                  className="h-full rounded-full bg-primary transition-all duration-300"
                  style={{
                    width: `${Math.max(8, (selfies.length / 5) * 100)}%`,
                  }}
                />
              </div>
            </div>
          ) : null}
          {selfies.length ? (
            <div className="flex flex-wrap gap-2">
              {selfies.map((file, index) => (
                <Badge
                  key={`${file.name}-${file.lastModified}-${index}`}
                  variant="outline"
                  className="gap-2 py-1.5"
                >
                  Selfie {index + 1}
                  <button
                    type="button"
                    aria-label={`Remove selfie ${index + 1}`}
                    onClick={() =>
                      setSelfies((current) =>
                        current.filter((_, itemIndex) => itemIndex !== index),
                      )
                    }
                  >
                    <Trash2 className="h-3 w-3" />
                  </button>
                </Badge>
              ))}
            </div>
          ) : null}
          {faceEnrollment || info.guestNotificationsEnabled ? (
            <>
              <div className="grid gap-3 sm:grid-cols-2">
                <div className="space-y-2">
                  <Label>Email {faceEnrollment ? "*" : ""}</Label>
                  <Input
                    type="email"
                    value={email}
                    onChange={(event) => setEmail(event.target.value)}
                    placeholder="you@example.com"
                  />
                </div>
                <div className="space-y-2">
                  <Label>WhatsApp {faceEnrollment ? "*" : ""}</Label>
                  <Input
                    value={whatsapp}
                    onChange={(event) => setWhatsapp(event.target.value)}
                    placeholder="+1..."
                  />
                </div>
              </div>
              {info.guestNotificationsEnabled ? (
                <div className="grid gap-2 sm:grid-cols-2">
                  {info.emailNotificationsEnabled !== false ? (
                    <Toggle
                      label="Email new matches"
                      checked={notifyEmail}
                      onChange={setNotifyEmail}
                    />
                  ) : (
                    <p className="rounded-xl border p-3 text-xs text-muted-foreground">
                      Email alerts are disabled for this event.
                    </p>
                  )}
                  {info.whatsappNotificationsEnabled === true ? (
                    <Toggle
                      label="WhatsApp new matches"
                      checked={notifyWhatsapp}
                      onChange={setNotifyWhatsapp}
                    />
                  ) : (
                    <p className="rounded-xl border p-3 text-xs text-muted-foreground">
                      WhatsApp alerts are disabled for this event.
                    </p>
                  )}
                </div>
              ) : (
                <p className="rounded-xl border p-3 text-xs text-muted-foreground">
                  This event has automatic match alerts turned off. Your
                  reusable face profile can still be created and used to find
                  matching photos.
                </p>
              )}
            </>
          ) : null}
          <label className="flex items-start gap-3 rounded-xl border p-3 text-sm">
            <Checkbox
              checked={consent}
              onCheckedChange={(value) => setConsent(value === true)}
            />
            <span>
              {faceEnrollment
                ? "I consent to a reusable global face profile. Face vectors and contact preferences can be reused at enabled events; original selfie files are not retained and I can delete the profile later."
                : "I consent to an event-scoped face profile for this gallery. My original selfie is not stored and I can delete the profile later."}
            </span>
          </label>
          <Button
            className="w-full"
            disabled={
              registering ||
              selfies.length < (faceEnrollment ? 2 : 1) ||
              !consent ||
              (faceEnrollment && (!email.trim() || !whatsapp.trim()))
            }
            onClick={() => void registerPersonalGallery()}
          >
            {registering ? (
              <Loader2 className="mr-2 h-4 w-4 animate-spin" />
            ) : (
              <Search className="mr-2 h-4 w-4" />
            )}
            {faceEnrollment
              ? "Create / update my global face profile"
              : "Create my personal gallery"}
          </Button>
        </div>
      </AccessShell>
    );
  }

  const visibleImages = images.slice(0, visibleCount);
  return (
    <div className="min-h-screen bg-background" style={style}>
      <section className="relative h-[300px] overflow-hidden bg-zinc-950 sm:h-[380px]">
        {cover ? (
          <img
            src={assetUrl(cover)}
            alt=""
            className="absolute inset-0 h-full w-full object-cover"
          />
        ) : (
          <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_top,_hsl(18_100%_58%/0.25),_transparent_60%)] bg-zinc-950" />
        )}
        <div className="absolute inset-0 bg-gradient-to-t from-black/80 via-black/25 to-black/40" />
        <button
          type="button"
          aria-label="View gallery photos"
          className="absolute bottom-5 left-1/2 flex h-11 w-11 -translate-x-1/2 items-center justify-center rounded-full border border-white/30 bg-white/10 text-white backdrop-blur transition hover:bg-white/20"
          onClick={() =>
            document
              .getElementById("gallery-grid")
              ?.scrollIntoView({ behavior: "smooth" })
          }
        >
          <ChevronDown className="h-5 w-5" />
        </button>
      </section>

      <main className="relative mx-auto max-w-[1500px] space-y-8 bg-background px-4 pb-16 pt-4 sm:px-6">
        <section className="-mt-14 rounded-3xl border bg-card p-5 sm:p-7">
          <div className="flex flex-col gap-6 lg:flex-row lg:items-start lg:justify-between">
            <div className="min-w-0">
              <div className="flex flex-wrap items-center gap-3">
                {albumId ? (
                  <Button
                    variant="outline"
                    size="icon"
                    asChild
                    aria-label="Back to event gallery"
                  >
                    <Link
                      to={`/event/${eventId}${accessToken ? `?access=${encodeURIComponent(accessToken)}` : ""}`}
                    >
                      <ArrowLeft className="h-4 w-4" />
                    </Link>
                  </Button>
                ) : null}
                <div className="flex h-11 w-11 items-center justify-center overflow-hidden rounded-full border bg-muted">
                  {branding.logoUrl ? (
                    <img
                      src={assetUrl(branding.logoUrl)}
                      alt=""
                      className="h-full w-full object-cover"
                    />
                  ) : (
                    <Camera className="h-5 w-5" />
                  )}
                </div>
                <p className="text-sm font-semibold tracking-tight">
                  {branding.whiteLabel ? info?.title : "airpix"}
                </p>
                <span className="inline-flex items-center gap-1.5 rounded-full border border-primary/20 bg-primary/5 px-2.5 py-0.5 text-xs font-medium text-primary">
                  <span className="relative flex h-1.5 w-1.5">
                    <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-primary opacity-60" />
                    <span className="relative inline-flex h-1.5 w-1.5 rounded-full bg-primary" />
                  </span>
                  Live
                </span>
                {guestToken ? (
                  <Badge variant="secondary">Your personal gallery</Badge>
                ) : null}
              </div>
              <h1 className="mt-5 text-2xl font-bold tracking-tight sm:text-4xl">
                {branding.coverText || info?.title}
              </h1>
              {info?.description ? (
                <p className="mt-2 max-w-2xl text-sm text-muted-foreground sm:text-base">
                  {info.description}
                </p>
              ) : null}
              <div className="mt-5 flex flex-wrap items-center gap-2">
                <span className="inline-flex items-center gap-2 rounded-full border bg-background px-3 py-1.5 text-sm font-medium">
                  <Images className="h-4 w-4 text-primary" />
                  {images.length} {guestToken ? "matching" : "published"} photos
                </span>
                {faceMatches ? (
                  <span className="inline-flex items-center gap-2 rounded-full border border-primary/20 bg-primary/5 px-3 py-1.5 text-sm font-medium text-primary">
                    <UserRoundSearch className="h-4 w-4" />
                    Face matches
                  </span>
                ) : null}
              </div>
            </div>

            <div className="flex flex-wrap items-center gap-2 lg:justify-end">
              {faceMatches ? (
                <Button
                  variant="outline"
                  size="sm"
                  onClick={() => void loadPublic()}
                >
                  <RefreshCw className="mr-2 h-4 w-4" /> Show all
                </Button>
              ) : null}
              {storeCatalog && storeCatalog.data.length ? (
                <Button
                  size="sm"
                  onClick={() =>
                    storeCatalog.settings.wholeEventPrice > 0
                      ? openPurchase([], "event")
                      : openPurchase(
                          storeCatalog.data.map((photo) => photo._id),
                        )
                  }
                >
                  <ShoppingCart className="mr-2 h-4 w-4" />
                  Buy all · {storeCatalog.settings.currency} {buyAllPrice.toFixed(2)}
                </Button>
              ) : null}
              <Button
                variant="outline"
                size="icon"
                disabled={downloading || images.length === 0}
                aria-label={
                  storeEnabled
                    ? selected.size
                      ? "Buy selected photos"
                      : "Buy photos"
                    : selected.size
                      ? "Download selected photos"
                      : "Download all photos"
                }
                onClick={() =>
                  storeEnabled ? buySelectedOrAll() : void download()
                }
              >
                {downloading ? (
                  <Loader2 className="h-4 w-4 animate-spin" />
                ) : storeEnabled ? (
                  <ShoppingCart className="h-4 w-4" />
                ) : (
                  <Download className="h-4 w-4" />
                )}
              </Button>
              <Button
                variant="outline"
                size="icon"
                aria-label="Share gallery"
                onClick={() => void shareGallery()}
              >
                <Share2 className="h-4 w-4" />
              </Button>
              <Button
                variant="outline"
                size="icon"
                aria-label={
                  selected.size ? "Clear selection" : "Select all photos"
                }
                onClick={() =>
                  setSelected(
                    selected.size
                      ? new Set()
                      : new Set(images.map((image) => imageId(image))),
                  )
                }
                disabled={!images.length}
              >
                <CheckCircle2 className="h-4 w-4" />
              </Button>
              <DropdownMenu>
                <DropdownMenuTrigger asChild>
                  <Button
                    variant="outline"
                    size="icon"
                    aria-label="More gallery actions"
                  >
                    <MoreHorizontal className="h-4 w-4" />
                  </Button>
                </DropdownMenuTrigger>
                <DropdownMenuContent align="end" className="w-44">
                  <DropdownMenuItem
                    onSelect={startSlideshow}
                    disabled={!images.length}
                  >
                    <Play className="mr-2 h-4 w-4" />
                    Slideshow
                  </DropdownMenuItem>
                  <DropdownMenuItem onSelect={() => void toggleFullscreen()}>
                    <Maximize2 className="mr-2 h-4 w-4" />
                    Full screen
                  </DropdownMenuItem>
                </DropdownMenuContent>
              </DropdownMenu>
              {guestToken ? (
                <Button
                  variant="outline"
                  size="icon"
                  aria-label="Delete selfie profile"
                  onClick={() => void deletePersonalGallery()}
                >
                  <Trash2 className="h-4 w-4" />
                </Button>
              ) : null}
            </div>
          </div>
        </section>

        {guestToken && info?.guestNotificationsEnabled ? (
          <Card>
            <CardContent className="space-y-3 p-4">
              <div>
                <p className="font-semibold">New photo alerts</p>
                <p className="text-xs text-muted-foreground">
                  Change how we notify you when new face matches arrive.
                </p>
              </div>
              <div className="grid gap-3 sm:grid-cols-2">
                <Input
                  value={email}
                  onChange={(event) => setEmail(event.target.value)}
                  placeholder="Email"
                />
                <Input
                  value={whatsapp}
                  onChange={(event) => setWhatsapp(event.target.value)}
                  placeholder="WhatsApp"
                />
              </div>
              <div className="grid gap-2 sm:grid-cols-2">
                <Toggle
                  label="Email alerts"
                  checked={notifyEmail}
                  onChange={setNotifyEmail}
                />
                <Toggle
                  label="WhatsApp alerts"
                  checked={notifyWhatsapp}
                  onChange={setNotifyWhatsapp}
                />
              </div>
              <Button
                size="sm"
                disabled={savingPreferences}
                onClick={() => void saveGuestPreferences()}
              >
                {savingPreferences ? (
                  <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                ) : null}
                Save alerts
              </Button>
            </CardContent>
          </Card>
        ) : null}

        {!albumId && albums.length && !guestToken ? (
          <section>
            <div className="mb-3 flex items-center gap-2">
              <Folder className="h-4 w-4 text-primary" />
              <h2 className="text-sm font-semibold uppercase tracking-wider text-muted-foreground">
                Albums
              </h2>
            </div>
            <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
              {albums.map((album) => (
                <Link
                  key={album._id || album.id}
                  to={`/event/${eventId}/album/${album._id || album.id}${accessToken ? `?access=${encodeURIComponent(accessToken)}` : ""}`}
                  className="group rounded-2xl border bg-card p-4 transition-all duration-300 hover:border-primary/50 hover:bg-muted/30"
                >
                  <div className="flex items-center justify-between">
                    <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-primary/10 transition-colors group-hover:bg-primary/15">
                      <Folder className="h-5 w-5 text-primary" />
                    </div>
                    <ChevronRight className="h-4 w-4 text-muted-foreground transition-transform duration-300 group-hover:translate-x-0.5" />
                  </div>
                  <p className="mt-3 font-semibold">{album.title || "Album"}</p>
                  <p className="mt-0.5 text-xs text-muted-foreground">
                    {album.imagesCount || 0} photos
                  </p>
                </Link>
              ))}
            </div>
          </section>
        ) : null}

        {loading ? (
          <div className="flex min-h-52 items-center justify-center">
            <Loader2 className="h-7 w-7 animate-spin" />
          </div>
        ) : visibleImages.length === 0 ? (
          <div className="flex min-h-64 flex-col items-center justify-center rounded-3xl border border-dashed bg-muted/20 text-center">
            <div className="flex h-14 w-14 items-center justify-center rounded-2xl bg-background">
              <Images className="h-7 w-7 text-muted-foreground" />
            </div>
            <p className="mt-4 font-semibold">
              {guestToken
                ? "No matching photos yet"
                : "No published photos yet"}
            </p>
            <p className="mt-1 max-w-md text-sm text-muted-foreground">
              {guestToken
                ? "Keep this page open. New matching photos appear automatically as the event continues."
                : "Published photos appear here in real time."}
            </p>
          </div>
        ) : (
          <div
            id="gallery-grid"
            className="columns-1 gap-1 sm:columns-2 lg:columns-3 xl:columns-4"
          >
            {visibleImages.map((image, index) => {
              const id = imageId(image);
              if (!id) return null;
              const isSelected = selected.has(id);
              return (
                <article
                  key={id}
                  className="group relative mb-4 break-inside-avoid overflow-hidden rounded-2xl border bg-black"
                >
                  {image.imageUrl ? (
                    image.mediaType === "video" ? (
                      <video
                        src={assetUrl(image.imageUrl)}
                        controls
                        preload="metadata"
                        className="aspect-video w-full object-cover"
                      />
                    ) : (
                      <button
                        type="button"
                        className="block w-full cursor-zoom-in"
                        aria-label={`Open event photo ${index + 1}`}
                        onClick={() => {
                          setFocusedIndex(index);
                          track("image_view", id);
                        }}
                      >
                        <img
                          src={assetUrl(image.imageUrl)}
                          alt={`Event photo ${index + 1}`}
                          loading="lazy"
                          className="h-auto w-full object-cover transition duration-500 group-hover:scale-[1.03]"
                        />
                      </button>
                    )
                  ) : (
                    <div className="flex aspect-[4/3] items-center justify-center bg-muted">
                      <ImageIcon className="h-8 w-8 text-muted-foreground" />
                    </div>
                  )}
                  {branding.watermarkUrl &&
                  branding.watermarkPosition === "tile" ? (
                    <div className="pointer-events-none absolute inset-0 grid grid-cols-3 grid-rows-2 place-items-center gap-3 p-4">
                      {Array.from({ length: 6 }, (_, watermarkIndex) => (
                        <img
                          key={watermarkIndex}
                          src={assetUrl(branding.watermarkUrl)}
                          alt=""
                          className="max-h-12 max-w-full object-contain"
                          style={{
                            opacity: branding.watermarkOpacity ?? 0.7,
                            width: `${Math.min(branding.watermarkScale ?? 24, 45)}%`,
                          }}
                        />
                      ))}
                    </div>
                  ) : branding.watermarkUrl ? (
                    <img
                      src={assetUrl(branding.watermarkUrl)}
                      alt=""
                      className={`pointer-events-none absolute max-h-[60%] object-contain ${watermarkPositionClass(branding.watermarkPosition)}`}
                      style={{
                        opacity: branding.watermarkOpacity ?? 0.7,
                        width: `${branding.watermarkScale ?? 24}%`,
                      }}
                    />
                  ) : null}
                  <label className="absolute left-3 top-3 rounded-full bg-background/90 p-1.5 opacity-0 shadow-sm transition group-hover:opacity-100 has-[:checked]:opacity-100">
                    <Checkbox
                      checked={isSelected}
                      onCheckedChange={() => toggle(id)}
                      aria-label="Select image"
                    />
                  </label>
                  <Button
                    size="icon"
                    className="absolute bottom-3 right-3 h-9 w-9 rounded-full bg-white text-black opacity-0 shadow-sm transition hover:bg-white hover:text-black group-hover:opacity-100"
                    aria-label={
                      image.purchaseRequired
                        ? "Buy original photo"
                        : "Download original photo"
                    }
                    onClick={() => void download([image])}
                  >
                    {image.purchaseRequired ? (
                      <ShoppingCart className="h-4 w-4" />
                    ) : (
                      <Download className="h-4 w-4" />
                    )}
                  </Button>
                  {image.isEnhanced ? (
                    <Badge className="absolute right-3 top-3">Enhanced</Badge>
                  ) : null}
                </article>
              );
            })}
          </div>
        )}

        {visibleCount < images.length ? (
          <div className="flex justify-center">
            <Button
              variant="outline"
              onClick={() =>
                setVisibleCount((count) =>
                  Math.min(count + pageSize, images.length),
                )
              }
            >
              Load more
            </Button>
          </div>
        ) : null}
      </main>

      {info?.faceSearchEnabled && !guestToken ? (
        <>
          <input
            ref={faceInput}
            type="file"
            accept={imageAccept}
            capture="user"
            className="hidden"
            onChange={(event) => {
              setFindMeOpen(false);
              void runFaceSearch(event);
            }}
          />
          <input
            ref={faceUploadInput}
            type="file"
            accept={imageAccept}
            className="hidden"
            onChange={(event) => {
              setFindMeOpen(false);
              void runFaceSearch(event);
            }}
          />
          <Button
            size="lg"
            className="fixed bottom-6 right-6 z-40 rounded-full bg-primary px-6 text-primary-foreground shadow-xl transition hover:brightness-110"
            disabled={faceSearching}
            onClick={() => setFindMeOpen(true)}
          >
            {faceSearching ? (
              <Loader2 className="mr-2 h-5 w-5 animate-spin" />
            ) : (
              <UserRoundSearch className="mr-2 h-5 w-5" />
            )}
            Find Me
          </Button>
        </>
      ) : null}

      {findMeOpen ? (
        <FindMeDialog
          busy={faceSearching}
          onClose={() => setFindMeOpen(false)}
          onCamera={() => faceInput.current?.click()}
          onUpload={() => faceUploadInput.current?.click()}
        />
      ) : null}

      <ShareDialog
        open={shareOpen}
        onOpenChange={setShareOpen}
        url={shareUrl}
        shareText={shareTitle}
        qrDataUrl={shareQr}
      />

      <Sheet open={purchaseOpen} onOpenChange={setPurchaseOpen}>
        <SheetContent
          side="bottom"
          className="max-h-[90vh] overflow-y-auto rounded-t-3xl px-4 pb-8 pt-6"
        >
          <div className="mx-auto w-full max-w-3xl space-y-6">
            <SheetHeader className="pr-8">
              <SheetTitle className="text-2xl">Purchase originals</SheetTitle>
              <SheetDescription>
                Complete payment securely with Stripe. Your full-resolution,
                unwatermarked photos will be delivered by email.
              </SheetDescription>
            </SheetHeader>

            {storeCatalog ? (
              <>
                <div className="grid gap-3 sm:grid-cols-2">
                  <button
                    type="button"
                    className={`rounded-2xl border p-4 text-left transition ${
                      purchaseMode === "selected"
                        ? "border-primary bg-primary/5"
                        : "hover:bg-muted/40"
                    }`}
                    onClick={() => setPurchaseMode("selected")}
                  >
                    <p className="font-semibold">
                      {purchaseIds.size} selected photo
                      {purchaseIds.size === 1 ? "" : "s"}
                    </p>
                    <p className="mt-1 text-sm text-muted-foreground">
                      {storeCatalog.settings.currency}{" "}
                      {(storeCatalog.settings.bundlePrice > 0 &&
                      purchaseIds.size >= storeCatalog.settings.bundleMinPhotos
                        ? storeCatalog.settings.bundlePrice
                        : storeCatalog.settings.singlePhotoPrice *
                          purchaseIds.size
                      ).toFixed(2)}
                    </p>
                  </button>
                  {storeCatalog.settings.wholeEventPrice > 0 ? (
                    <button
                      type="button"
                      className={`rounded-2xl border p-4 text-left transition ${
                        purchaseMode === "event"
                          ? "border-primary bg-primary/5"
                          : "hover:bg-muted/40"
                      }`}
                      onClick={() => setPurchaseMode("event")}
                    >
                      <p className="font-semibold">
                        Buy all {storeCatalog.totalItems} photos
                      </p>
                      <p className="mt-1 text-sm text-muted-foreground">
                        {storeCatalog.settings.currency}{" "}
                        {storeCatalog.settings.wholeEventPrice.toFixed(2)}
                      </p>
                    </button>
                  ) : null}
                </div>

                <div className="grid gap-4 sm:grid-cols-2">
                  <div className="space-y-2">
                    <Label>Email for delivery</Label>
                    <Input
                      type="email"
                      value={email}
                      onChange={(event) => setEmail(event.target.value)}
                      placeholder="you@example.com"
                    />
                  </div>
                  <div className="space-y-2">
                    <Label>WhatsApp (optional)</Label>
                    <Input
                      value={whatsapp}
                      onChange={(event) => setWhatsapp(event.target.value)}
                      placeholder="+1..."
                    />
                  </div>
                </div>

                <div className="flex flex-col gap-3 rounded-2xl bg-muted/40 p-4 sm:flex-row sm:items-center sm:justify-between">
                  <div>
                    <p className="text-sm text-muted-foreground">
                      {purchaseMode === "event"
                        ? `${storeCatalog.totalItems} event photos`
                        : `${purchaseIds.size} selected photo${
                            purchaseIds.size === 1 ? "" : "s"
                          }`}
                    </p>
                    <p className="text-2xl font-bold">
                      {storeCatalog.settings.currency}{" "}
                      {purchasePrice.toFixed(2)}
                    </p>
                  </div>
                  <Button
                    size="lg"
                    disabled={
                      checkingOut ||
                      !email.trim() ||
                      (purchaseMode === "selected" && !purchaseIds.size)
                    }
                    onClick={() => void startCheckout()}
                  >
                    {checkingOut ? (
                      <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                    ) : (
                      <ShoppingCart className="mr-2 h-4 w-4" />
                    )}
                    Continue to secure checkout
                  </Button>
                </div>

                {storeCatalog.settings.termsText ? (
                  <p className="text-xs text-muted-foreground">
                    {storeCatalog.settings.termsText}
                  </p>
                ) : null}
              </>
            ) : (
              <div className="flex min-h-32 items-center justify-center">
                <Loader2 className="h-6 w-6 animate-spin" />
              </div>
            )}
          </div>
        </SheetContent>
      </Sheet>

      {focusedImage ? (
        <GalleryLightbox
          image={focusedImage}
          imageUrl={assetUrl(focusedImage.imageUrl)}
          position={focusedIndex + 1}
          total={images.length}
          onClose={closeFocusedImage}
          slideshow={slideshow}
          onPrevious={() =>
            setFocusedIndex(
              (index) => (index - 1 + images.length) % images.length,
            )
          }
          onNext={() => setFocusedIndex((index) => (index + 1) % images.length)}
          onToggleSlideshow={() => setSlideshow((value) => !value)}
          onFullscreen={() => void toggleFullscreen()}
          onShare={() => void shareGallery(focusedImage)}
          onPrimaryAction={() => {
            if (focusedImage.purchaseRequired) {
              const storeId =
                focusedImage.storeImageId || imageId(focusedImage);
              closeFocusedImage();
              openPurchase([storeId]);
            } else {
              void download([focusedImage]);
            }
          }}
        />
      ) : null}

      <footer className="border-t bg-background">
        <div className="mx-auto max-w-[1500px] px-4 py-6 text-sm text-muted-foreground sm:px-6">
          {branding.footerText ||
            (!branding.whiteLabel ? "Live photo delivery by airpix" : "")}
          {branding.sponsorText ? (
            <p className="mt-1">{branding.sponsorText}</p>
          ) : null}
        </div>
      </footer>
    </div>
  );
}

export function FindMeDialog({
  busy,
  onClose,
  onCamera,
  onUpload,
}: {
  busy: boolean;
  onClose: () => void;
  onCamera: () => void;
  onUpload: () => void;
}) {
  return (
    <div
      className="fixed inset-0 z-[70] flex items-center justify-center bg-black/65 p-4"
      role="dialog"
      aria-modal="true"
      aria-labelledby="find-me-title"
    >
      <div className="relative w-full max-w-md rounded-3xl border bg-background p-6">
        <Button
          variant="ghost"
          size="icon"
          className="absolute right-3 top-3"
          aria-label="Close Find Me"
          onClick={onClose}
        >
          <X className="h-5 w-5" />
        </Button>
        <div className="mb-4 flex h-12 w-12 items-center justify-center rounded-2xl bg-primary/10">
          <UserRoundSearch className="h-6 w-6 text-primary" />
        </div>
        <h2 id="find-me-title" className="text-2xl font-bold tracking-tight">
          Find all your photos
        </h2>
        <p className="mt-2 text-sm text-muted-foreground">
          Take a clear selfie now or upload one from your device. Face matching
          will show every photo of you in this event.
        </p>
        <div className="mt-6 grid gap-3 sm:grid-cols-2">
          <Button
            className="h-24 flex-col gap-2"
            disabled={busy}
            onClick={onCamera}
          >
            <Camera className="h-6 w-6" />
            Take a photo
          </Button>
          <Button
            className="h-24 flex-col gap-2"
            variant="outline"
            disabled={busy}
            onClick={onUpload}
          >
            <Upload className="h-6 w-6" />
            Upload a selfie
          </Button>
        </div>
        <p className="mt-4 text-xs text-muted-foreground">
          Your selfie is used only to search this gallery unless you explicitly
          create a reusable face profile.
        </p>
      </div>
    </div>
  );
}

function GalleryLightbox({
  image,
  imageUrl,
  position,
  total,
  slideshow,
  onClose,
  onPrevious,
  onNext,
  onToggleSlideshow,
  onFullscreen,
  onShare,
  onPrimaryAction,
}: {
  image: GalleryImage;
  imageUrl: string;
  position: number;
  total: number;
  slideshow: boolean;
  onClose: () => void;
  onPrevious: () => void;
  onNext: () => void;
  onToggleSlideshow: () => void;
  onFullscreen: () => void;
  onShare: () => void;
  onPrimaryAction: () => void;
}) {
  return (
    <div
      className="fixed inset-0 z-[60] flex items-center justify-center bg-black/95 text-white backdrop-blur-sm"
      role="dialog"
      aria-modal="true"
      aria-label="Photo viewer"
    >
      <div className="absolute inset-x-0 top-0 z-10 flex items-center justify-between bg-gradient-to-b from-black/80 to-transparent p-3 pb-10 sm:p-5 sm:pb-12">
        <Button
          variant="ghost"
          size="icon"
          className="text-white hover:bg-white/10 hover:text-white"
          aria-label="Close photo"
          onClick={onClose}
        >
          <ArrowLeft className="h-6 w-6" />
        </Button>
        <div className="flex items-center gap-1">
          <Button
            variant={image.purchaseRequired ? "secondary" : "ghost"}
            size={image.purchaseRequired ? "sm" : "icon"}
            className={
              image.purchaseRequired
                ? "bg-white text-black hover:bg-white/90"
                : "text-white hover:bg-white/10 hover:text-white"
            }
            aria-label={
              image.purchaseRequired
                ? "Buy this photo"
                : "Download original photo"
            }
            onClick={onPrimaryAction}
          >
            {image.purchaseRequired ? (
              <>
                <ShoppingCart className="mr-2 h-4 w-4" />
                Buy this photo
              </>
            ) : (
              <Download className="h-5 w-5" />
            )}
          </Button>
          <Button
            variant="ghost"
            size="icon"
            className="text-white hover:bg-white/10 hover:text-white"
            aria-label="Share photo"
            onClick={onShare}
          >
            <Share2 className="h-5 w-5" />
          </Button>
          <Button
            variant="ghost"
            size="icon"
            className="text-white hover:bg-white/10 hover:text-white"
            aria-label={slideshow ? "Pause slideshow" : "Start slideshow"}
            onClick={onToggleSlideshow}
          >
            {slideshow ? (
              <Pause className="h-5 w-5" />
            ) : (
              <Play className="h-5 w-5" />
            )}
          </Button>
          <Button
            variant="ghost"
            size="icon"
            className="text-white hover:bg-white/10 hover:text-white"
            aria-label="Full screen"
            onClick={onFullscreen}
          >
            <Maximize2 className="h-5 w-5" />
          </Button>
        </div>
      </div>
      {total > 1 ? (
        <>
          <Button
            variant="ghost"
            size="icon"
            className="absolute left-2 z-10 text-white hover:bg-white/10 hover:text-white sm:left-5"
            aria-label="Previous photo"
            onClick={onPrevious}
          >
            <ChevronLeft className="h-8 w-8" />
          </Button>
          <Button
            variant="ghost"
            size="icon"
            className="absolute right-2 z-10 text-white hover:bg-white/10 hover:text-white sm:right-5"
            aria-label="Next photo"
            onClick={onNext}
          >
            <ChevronRight className="h-8 w-8" />
          </Button>
        </>
      ) : null}
      {image.mediaType === "video" ? (
        <video
          src={imageUrl}
          controls
          autoPlay
          className="max-h-screen max-w-full"
        />
      ) : (
        <img
          src={imageUrl}
          alt={`Event photo ${position}`}
          className="max-h-screen max-w-full object-contain"
        />
      )}
      <div className="absolute bottom-4 left-1/2 -translate-x-1/2 rounded-full border border-white/10 bg-black/60 px-4 py-1.5 text-xs backdrop-blur">
        {position} / {total}
        {image.purchaseRequired
          ? " · Preview — purchase unlocks the original"
          : ""}
      </div>
    </div>
  );
}

function SocialShareButton({
  href,
  label,
  className,
  icon,
}: {
  href: string;
  label: string;
  className?: string;
  icon: ReactNode;
}) {
  return (
    <a
      href={href}
      target="_blank"
      rel="noopener noreferrer"
      aria-label={label}
      title={label}
      className={`flex h-11 w-11 items-center justify-center rounded-full text-white transition duration-300 hover:scale-110 ${className ?? ""}`}
    >
      {icon}
    </a>
  );
}

function ShareDialog({
  open,
  onOpenChange,
  url,
  shareText,
  qrDataUrl,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  url: string;
  shareText: string;
  qrDataUrl: string;
}) {
  const [copied, setCopied] = useState(false);

  useEffect(() => {
    if (!open) setCopied(false);
  }, [open]);

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(url);
      setCopied(true);
      toast.success("Link copied");
    } catch {
      toast.error("Could not copy the link");
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md gap-0 overflow-hidden rounded-3xl p-0">
        <DialogHeader className="space-y-1 border-b p-6 pb-5">
          <DialogTitle className="text-xl font-bold tracking-tight">
            Share
          </DialogTitle>
          <DialogDescription>
            Let anyone with the link see the{' '}
            {url.includes("/image/") ? "photo" : "gallery"}
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-5 p-6">
          <div className="flex items-center justify-between gap-2">
            <SocialShareButton
              href={socialShareUrl("facebook", url, shareText)}
              label="Share on Facebook"
              className="bg-[#1877F2] hover:brightness-110"
              icon={
                <svg viewBox="0 0 24 24" className="h-5 w-5" fill="currentColor">
                  <path d="M13.5 21v-7h2.4l.4-3h-2.8V9.1c0-.9.3-1.5 1.6-1.5h1.3V4.9c-.3 0-1.1-.1-2.1-.1-2.1 0-3.6 1.3-3.6 3.7V11H8.3v3h2.4v7h2.8z" />
                </svg>
              }
            />
            <SocialShareButton
              href={socialShareUrl("x", url, shareText)}
              label="Share on X"
              className="bg-zinc-900 hover:brightness-125"
              icon={
                <svg viewBox="0 0 24 24" className="h-4 w-4" fill="currentColor">
                  <path d="M17.8 3h3l-6.7 7.7L22 21h-6.2l-4.8-6.3L5.4 21h-3l7.2-8.2L2 3h6.4l4.4 5.8L17.8 3zm-1 16.2h1.7L7.5 4.7H5.7l11.1 14.5z" />
                </svg>
              }
            />
            <SocialShareButton
              href={socialShareUrl("pinterest", url, shareText)}
              label="Share on Pinterest"
              className="bg-[#E60023] hover:brightness-110"
              icon={
                <svg viewBox="0 0 24 24" className="h-5 w-5" fill="currentColor">
                  <path d="M12 2C6.5 2 2 6.5 2 12c0 4.2 2.6 7.8 6.3 9.3-.1-.8-.2-2 0-2.9.2-.8 1.2-5.1 1.2-5.1s-.3-.6-.3-1.5c0-1.4.8-2.5 1.9-2.5.9 0 1.3.7 1.3 1.5 0 .9-.6 2.2-.9 3.4-.2 1 .5 1.9 1.5 1.9 1.8 0 3.2-1.9 3.2-4.7 0-2.5-1.8-4.2-4.3-4.2-2.9 0-4.6 2.2-4.6 4.5 0 .9.3 1.8.8 2.4.1.1.1.2.1.3-.1.3-.2 1-.3 1.1 0 .2-.1.2-.3.1-1.2-.6-2-2.4-2-3.9 0-3.2 2.3-6.1 6.7-6.1 3.5 0 6.2 2.5 6.2 5.8 0 3.5-2.2 6.3-5.3 6.3-1 0-2-.5-2.3-1.2l-.6 2.4c-.2.9-.8 2-1.2 2.6.9.3 1.9.4 2.9.4 5.5 0 10-4.5 10-10S17.5 2 12 2z" />
                </svg>
              }
            />
            <SocialShareButton
              href={socialShareUrl("whatsapp", url, shareText)}
              label="Share on WhatsApp"
              className="bg-[#25D366] hover:brightness-110"
              icon={
                <svg viewBox="0 0 24 24" className="h-5 w-5" fill="currentColor">
                  <path d="M12 2a10 10 0 0 0-8.7 15L2 22l5.2-1.3A10 10 0 1 0 12 2zm0 18.2c-1.6 0-3.1-.4-4.4-1.2l-.3-.2-3.1.8.8-3-.2-.3A8.2 8.2 0 1 1 12 20.2zm4.6-6.1c-.3-.1-1.5-.7-1.7-.8-.2-.1-.4-.1-.6.1-.2.3-.6.8-.8 1-.1.2-.3.2-.5.1a6.7 6.7 0 0 1-3.4-3c-.3-.4 0-.5.1-.7l.4-.5c.1-.2.2-.3.3-.5.1-.2 0-.4 0-.5l-.8-1.9c-.2-.5-.4-.4-.6-.4h-.5c-.2 0-.5.1-.7.3-.2.3-.9.9-.9 2.2s.9 2.5 1.1 2.7c.1.2 1.8 2.8 4.4 3.9 2.6 1.1 2.6.7 3.1.7.5-.1 1.5-.6 1.7-1.2.2-.6.2-1.1.2-1.2-.1-.2-.3-.2-.5-.3z" />
                </svg>
              }
            />
            <SocialShareButton
              href={socialShareUrl("email", url, shareText)}
              label="Share by email"
              className="bg-zinc-400 hover:brightness-110"
              icon={<Mail className="h-5 w-5" />}
            />
          </div>

          <div className="flex items-center gap-2 rounded-xl border bg-muted/30 p-2 pl-4">
            <p className="min-w-0 flex-1 truncate text-sm text-foreground">
              {url}
            </p>
            <Button
              variant="ghost"
              size="sm"
              className="h-9 shrink-0 gap-1.5 rounded-lg px-3 text-muted-foreground hover:text-foreground"
              onClick={() => void copy()}
            >
              {copied ? (
                <Check className="h-4 w-4 text-primary" />
              ) : (
                <Copy className="h-4 w-4" />
              )}
              {copied ? "Copied" : "Copy"}
            </Button>
          </div>

          <Separator />

          {qrDataUrl ? (
            <div className="flex flex-col items-center gap-4">
              <img
                src={qrDataUrl}
                alt="QR code for this gallery"
                className="h-56 w-56"
              />
              <p className="text-center text-xs text-muted-foreground">
                Scan to open on any phone
              </p>
            </div>
          ) : null}
        </div>
      </DialogContent>
    </Dialog>
  );
}

function AccessShell({
  info,
  branding,
  cover,
  style,
  children,
}: {
  info?: GalleryInfo;
  branding: Branding;
  cover?: string;
  style: CSSProperties;
  children: ReactNode;
}) {
  return (
    <div className="min-h-screen bg-muted/20" style={style}>
      <div className="relative flex min-h-screen items-center justify-center overflow-hidden p-4">
        {cover ? (
          <img
            src={cover}
            alt=""
            className="absolute inset-0 h-full w-full object-cover"
          />
        ) : null}
        <div className="absolute inset-0 bg-black/50" />
        <div className="relative z-10 w-full">
          <div className="mx-auto mb-5 flex max-w-lg items-center justify-center gap-3">
            {branding.logoUrl ? (
              <img
                src={branding.logoUrl}
                alt=""
                className="max-h-12 max-w-40 object-contain"
              />
            ) : null}
            <p className="text-center text-lg font-bold text-white">
              {info?.title}
            </p>
          </div>
          <div className="mx-auto max-w-lg rounded-3xl border bg-background/95 p-6 backdrop-blur">
            {children}
          </div>
        </div>
      </div>
    </div>
  );
}

function EnrollmentStep({
  number,
  label,
  done,
}: {
  number: string;
  label: string;
  done: boolean;
}) {
  return (
    <div
      className={`rounded-xl border p-2.5 text-center transition-all duration-200 ${done ? "border-primary/30 bg-primary/5" : "bg-muted/20"}`}
    >
      <div className="mx-auto flex h-7 w-7 items-center justify-center rounded-full border bg-background text-xs font-bold">
        {done ? <CheckCircle2 className="h-4 w-4 text-primary" /> : number}
      </div>
      <p className="mt-1.5 text-[11px] font-medium">{label}</p>
    </div>
  );
}

function Toggle({
  label,
  checked,
  onChange,
}: {
  label: string;
  checked: boolean;
  onChange: (value: boolean) => void;
}) {
  return (
    <div className="flex items-center justify-between rounded-xl border p-3">
      <span className="text-xs font-medium">{label}</span>
      <Switch checked={checked} onCheckedChange={onChange} />
    </div>
  );
}
