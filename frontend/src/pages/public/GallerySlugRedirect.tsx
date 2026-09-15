import { useEffect } from "react";
import { Navigate, useParams } from "react-router-dom";
import { Loader2 } from "lucide-react";
import { useQueryWrapper } from "@/api-hooks/react-query-wrapper";

type ResolveResponse = { eventId: string };

export default function GallerySlugRedirect() {
  const { slug = "" } = useParams();
  const result = useQueryWrapper<ResolveResponse>(
    ["gallery-slug", slug],
    `/gallery-access/resolve?slug=${encodeURIComponent(slug)}`,
    { withCredentials: false, enabled: Boolean(slug), retry: false },
  );

  useEffect(() => {
    if (result.error) document.title = "Gallery not found";
  }, [result.error]);

  if (result.data?.eventId) {
    return <Navigate to={`/event/${result.data.eventId}`} replace />;
  }
  if (result.error) {
    return <div className="flex min-h-screen items-center justify-center p-6 text-center"><div><h1 className="text-2xl font-bold">Gallery not found</h1><p className="mt-2 text-sm text-muted-foreground">Check the gallery link with the event organizer.</p></div></div>;
  }
  return <div className="flex min-h-screen items-center justify-center"><Loader2 className="h-7 w-7 animate-spin" /></div>;
}
