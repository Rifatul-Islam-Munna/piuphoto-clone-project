import { createContext, ReactNode, useContext, useEffect, useMemo, useState } from "react";
import { useQueryWrapper } from "@/api-hooks/react-query-wrapper";
import {
  defaultSiteSettings,
  getLocalizedText,
  LanguageCode,
  mergeSiteSettings,
  SiteSettings,
  SiteSettingsResponse,
} from "@/lib/site-settings";

type SiteSettingsContextValue = {
  settings: SiteSettings;
  language: LanguageCode;
  setLanguage: (language: LanguageCode) => void;
  isLoading: boolean;
  t: (value: { en: string; gr: string } | undefined) => string;
};

const SiteSettingsContext = createContext<SiteSettingsContextValue | null>(null);

const FAVICON_ID = "site-settings-favicon";

export function SiteSettingsProvider({ children }: { children: ReactNode }) {
  const [language, setLanguageState] = useState<LanguageCode>(() => {
    if (typeof window === "undefined") return "en";
    const stored = window.localStorage.getItem("site-language");
    return stored === "gr" ? "gr" : "en";
  });

  const { data, isLoading } = useQueryWrapper<SiteSettingsResponse>(
    ["site-settings-public"],
    "/settings/public",
    { withCredentials: true },
  );

  const settings = useMemo(
    () => mergeSiteSettings(defaultSiteSettings, data?.data),
    [data],
  );

  useEffect(() => {
    if (typeof window === "undefined") return;
    window.localStorage.setItem("site-language", language);
  }, [language]);

  useEffect(() => {
    if (typeof document === "undefined") return;

    document.title = settings.site.title || defaultSiteSettings.site.title;

    let link = document.getElementById(FAVICON_ID) as HTMLLinkElement | null;
    const logoUrl = settings.site.logoUrl?.trim();
    if (!logoUrl) {
      if (link) {
        link.href = "/favicon.ico";
      }
      return;
    }

    if (!link) {
      link = document.createElement("link");
      link.id = FAVICON_ID;
      link.rel = "icon";
      document.head.appendChild(link);
    }
    link.href = logoUrl;
  }, [settings.site.logoUrl, settings.site.title]);

  const value = useMemo<SiteSettingsContextValue>(
    () => ({
      settings,
      language,
      setLanguage: setLanguageState,
      isLoading,
      t: (text) => getLocalizedText(text, language),
    }),
    [settings, language, isLoading],
  );

  return (
    <SiteSettingsContext.Provider value={value}>
      {children}
    </SiteSettingsContext.Provider>
  );
}

export function useSiteSettings() {
  const context = useContext(SiteSettingsContext);
  if (!context) {
    throw new Error("useSiteSettings must be used inside SiteSettingsProvider");
  }
  return context;
}
