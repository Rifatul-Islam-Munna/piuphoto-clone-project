import { useEffect, useState } from "react";
import { Navigate } from "react-router-dom";
import { GetRequestAxios } from "@/api-hooks/api-hooks";
import Index from "../Index";

type ResolveResponse = { eventId?: string };

export default function DomainRoot() {
  const [eventId, setEventId] = useState<string>();
  const [resolved, setResolved] = useState(false);

  useEffect(() => {
    let active = true;
    const host = window.location.hostname.toLowerCase();
    if (!host || host === "localhost" || host === "127.0.0.1") {
      setResolved(true);
      return () => { active = false; };
    }
    void (async () => {
      const [data] = await GetRequestAxios<ResolveResponse>(
        `/gallery-access/resolve?domain=${encodeURIComponent(host)}`,
        { withCredentials: false, redirectOnUnauthorized: false },
      );
      if (!active) return;
      setEventId(data?.eventId);
      setResolved(true);
    })();
    return () => { active = false; };
  }, []);

  if (eventId) return <Navigate to={`/event/${eventId}`} replace />;
  if (!resolved) return <div className="min-h-screen bg-background" />;
  return <Index />;
}
