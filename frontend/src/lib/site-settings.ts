export type LanguageCode = "en" | "gr";

export type LocalizedText = {
  en: string;
  gr: string;
};

export type LocalizedLink = {
  label: LocalizedText;
  href: string;
};

export type SiteSettings = {
  key: string;
  site: {
    title: string;
    logoUrl: string;
  };
  navbar: {
    menuItems: LocalizedLink[];
    loginLabel: LocalizedText;
    dashboardLabel: LocalizedText;
    profileLabel: LocalizedText;
    logoutLabel: LocalizedText;
  };
  hero: {
    titleSuffix: LocalizedText;
    description: LocalizedText;
    appStoreText: LocalizedText;
    playStoreText: LocalizedText;
  };
  featuresGrid: {
    items: Array<{
      icon: string;
      variant: "yellow" | "blue" | "purple" | "pink";
      title: LocalizedText;
      description: LocalizedText;
    }>;
  };
  flyPhotos: {
    heading: LocalizedText;
    description: LocalizedText;
  };
  eventStreaming: {
    heading: LocalizedText;
    chips: LocalizedText[];
    ctaLabel: LocalizedText;
    features: LocalizedText[];
  };
  apiSection: {
    heading: LocalizedText;
    description: LocalizedText;
    cardTitle: LocalizedText;
    features: LocalizedText[];
  };
  connectionSection: {
    heading: LocalizedText;
    description: LocalizedText;
    wiredTitle: LocalizedText;
    wiredDescription: LocalizedText;
    wirelessTitle: LocalizedText;
    wirelessDescription: LocalizedText;
    ctaLabel: LocalizedText;
  };
  trustedBrands: {
    heading: LocalizedText;
    brands: string[];
  };
  caseStudy: {
    quote: LocalizedText;
    name: string;
    title: LocalizedText;
    company: LocalizedText;
  };
  newsroom: {
    heading: LocalizedText;
    description: LocalizedText;
    readMoreLabel: LocalizedText;
    items: Array<{
      date: string;
      title: LocalizedText;
      excerpt: LocalizedText;
    }>;
  };
  finalCta: {
    heading: LocalizedText;
    description: LocalizedText;
    appStoreText: LocalizedText;
    playStoreText: LocalizedText;
  };
  footer: {
    description: LocalizedText;
    featuresHeading: LocalizedText;
    companyHeading: LocalizedText;
    contactHeading: LocalizedText;
    copyrightText: LocalizedText;
    featuresLinks: LocalizedLink[];
    companyLinks: LocalizedLink[];
    contactLinks: LocalizedLink[];
    legalLinks: LocalizedLink[];
  };
};

export type SiteSettingsResponse = {
  data: SiteSettings;
};

export const defaultSiteSettings: SiteSettings = {
  key: "website",
  site: {
    title: "nikofly",
    logoUrl: "",
  },
  navbar: {
    menuItems: [
      { label: { en: "Try our event", gr: "Δοκιμασε την εκδηλωση" }, href: "#event" },
      { label: { en: "AI Magic", gr: "Μαγεια AI" }, href: "#ai-magic" },
      { label: { en: "API", gr: "API" }, href: "#api" },
      { label: { en: "Connect & Transfer", gr: "Συνδεση και μεταφορα" }, href: "#connect" },
      { label: { en: "Pricing", gr: "Τιμες" }, href: "/pricing" },
      { label: { en: "Case Studies", gr: "Μελετες περιπτωσης" }, href: "#case-studies" },
      { label: { en: "Features", gr: "Δυνατοτητες" }, href: "#features" },
    ],
    loginLabel: { en: "Login", gr: "Συνδεση" },
    dashboardLabel: { en: "Dashboard", gr: "Πινακας" },
    profileLabel: { en: "Profile", gr: "Προφιλ" },
    logoutLabel: { en: "Logout", gr: "Αποσυνδεση" },
  },
  hero: {
    titleSuffix: { en: "Photos Can Fly", gr: "Οι φωτογραφιες μπορουν να πεταξουν" },
    description: {
      en: "An event live streaming photos solution to let photographers & guests enjoy photos as easy as ABC",
      gr: "Λυση ζωντανης μεταδοσης φωτογραφιων για εκδηλωσεις, ωστε φωτογραφοι και καλεσμενοι να απολαμβανουν φωτογραφιες πανευκολα",
    },
    appStoreText: { en: "Download on App Store", gr: "Ληψη στο App Store" },
    playStoreText: { en: "Get it on Google Play", gr: "Ληψη στο Google Play" },
  },
  featuresGrid: {
    items: [
      {
        icon: "📱",
        variant: "yellow",
        title: { en: "Real-Time Photo Transfer", gr: "Μεταφορα φωτογραφιων σε πραγματικο χρονο" },
        description: { en: "Photos fly from camera to phone instantly", gr: "Οι φωτογραφιες πετουν απο καμερα σε κινητο αμεσα" },
      },
      {
        icon: "⚡",
        variant: "blue",
        title: { en: "Lightning Fast", gr: "Αστραπιαια ταχυτητα" },
        description: { en: "Upload speeds optimized for events", gr: "Ταχυτητες ανεβασματος βελτιστοποιημενες για εκδηλωσεις" },
      },
      {
        icon: "🎯",
        variant: "purple",
        title: { en: "Event-Based Sorting", gr: "Ταξινομηση ανα εκδηλωση" },
        description: { en: "Organize photos by event automatically", gr: "Οργανωστε φωτογραφιες ανα εκδηλωση αυτοματα" },
      },
      {
        icon: "🔒",
        variant: "pink",
        title: { en: "Secure & Private", gr: "Ασφαλες και ιδιωτικο" },
        description: { en: "Enterprise-grade security for your photos", gr: "Ασφαλεια επιπεδου enterprise για τις φωτογραφιες σας" },
      },
    ],
  },
  flyPhotos: {
    heading: { en: "Fly Your Photos Everywhere", gr: "Στειλτε τις φωτογραφιες σας παντου" },
    description: {
      en: "From camera to phone to social media - share your moments instantly",
      gr: "Απο την καμερα στο κινητο και στα social media - μοιραστειτε τις στιγμες σας αμεσα",
    },
  },
  eventStreaming: {
    heading: {
      en: "Instant Event Streaming and Photo Organization",
      gr: "Αμεση μεταδοση εκδηλωσης και οργανωση φωτογραφιων",
    },
    chips: [
      { en: "AI Selection", gr: "Επιλογη AI" },
      { en: "AI Beautify", gr: "Βελτιωση AI" },
    ],
    ctaLabel: { en: "Get Started", gr: "Ξεκινηστε" },
    features: [
      { en: "AI-powered photo selection and curation", gr: "Επιλογη και επιμελεια φωτογραφιων με AI" },
      { en: "Automatic enhancement and beautification", gr: "Αυτοματη βελτιωση και ομορφυνση" },
      { en: "Real-time streaming to all guests", gr: "Ζωντανη μεταδοση σε ολους τους καλεσμενους" },
      { en: "Instant social media sharing", gr: "Αμεσο διαμοιρασμο στα social media" },
      { en: "Cloud backup for all photos", gr: "Cloud backup για ολες τις φωτογραφιες" },
    ],
  },
  apiSection: {
    heading: { en: "API Integration for Every Company", gr: "Ενσωματωση API για καθε εταιρεια" },
    description: {
      en: "Seamlessly integrate nikofly into your existing workflow",
      gr: "Ενσωματωστε το nikofly ομαλα στην υπαρχουσα ροη εργασιας σας",
    },
    cardTitle: {
      en: "Integrate nikofly in your product or website with ease",
      gr: "Ενσωματωστε το nikofly στο προϊον ή στην ιστοσελιδα σας ευκολα",
    },
    features: [
      { en: "Simple REST API with comprehensive documentation", gr: "Απλο REST API με πληρη τεκμηριωση" },
      { en: "Real-time webhooks for instant updates", gr: "Realtime webhooks για αμεσες ενημερωσεις" },
      { en: "SDKs for all major platforms", gr: "SDKs για ολες τις βασικες πλατφορμες" },
      { en: "99.9% uptime SLA guarantee", gr: "Εγγυηση SLA 99.9% uptime" },
    ],
  },
  connectionSection: {
    heading: { en: "Plug & Play or Go Wireless", gr: "Συνδεστε αμεσα ή ασυρματα" },
    description: {
      en: "Connect your camera to your phone in seconds - wired or wireless",
      gr: "Συνδεστε την καμερα σας με το κινητο σε δευτερολεπτα - ενσυρματα ή ασυρματα",
    },
    wiredTitle: { en: "Wired (OTG Cable)", gr: "Ενσυρματα (καλωδιο OTG)" },
    wiredDescription: {
      en: "Connect directly with an OTG cable for the fastest, most reliable transfer speeds",
      gr: "Συνδεθειτε απευθειας με καλωδιο OTG για την πιο γρηγορη και αξιοπιστη μεταφορα",
    },
    wirelessTitle: { en: "Wireless (FTP)", gr: "Ασυρματα (FTP)" },
    wirelessDescription: {
      en: "Go cable-free with FTP connection for ultimate flexibility during events",
      gr: "Χωρις καλωδια με συνδεση FTP για μεγιστη ευελιξια στις εκδηλωσεις",
    },
    ctaLabel: { en: "Get Started", gr: "Ξεκινηστε" },
  },
  trustedBrands: {
    heading: { en: "Trusted by Top Brands", gr: "Εμπιστοσυνη απο κορυφαια brands" },
    brands: [
      "Canon", "Nikon", "Sony", "Adobe", "Capture One", "Lightroom",
      "DJI", "GoPro", "Leica", "Fujifilm", "Olympus", "Panasonic",
      "Hasselblad", "Phase One", "Sigma", "Tamron", "Profoto", "Godox",
      "Peak Design", "Think Tank", "Lowepro", "Manfrotto", "SanDisk", "Lexar",
    ],
  },
  caseStudy: {
    quote: {
      en: "nikofly transformed how we deliver wedding photos. Guests can now see and share their photos in real-time, creating an unforgettable experience. Our client satisfaction has never been higher.",
      gr: "Το nikofly μεταμορφωσε τον τροπο που παραδιδουμε φωτογραφιες γαμου. Οι καλεσμενοι μπορουν τωρα να βλεπουν και να μοιραζονται φωτογραφιες σε πραγματικο χρονο, δημιουργωντας αξέχαστη εμπειρια. Η ικανοποιηση των πελατων μας δεν ηταν ποτε υψηλοτερη.",
    },
    name: "Sarah Chen",
    title: { en: "Lead Photographer", gr: "Επικεφαλης φωτογραφος" },
    company: { en: "Eternal Moments Photography", gr: "Eternal Moments Photography" },
  },
  newsroom: {
    heading: { en: "Newsroom", gr: "Νεα" },
    description: { en: "Stay updated with the latest from nikofly", gr: "Μεινετε ενημερωμενοι με τα νεα του nikofly" },
    readMoreLabel: { en: "Read more", gr: "Διαβαστε περισσοτερα" },
    items: [
      {
        date: "Jan 15, 2026",
        title: {
          en: "nikofly Launches AI-Powered Photo Selection Feature",
          gr: "Το nikofly λανσαρει δυνατοτητα επιλογης φωτογραφιων με AI",
        },
        excerpt: {
          en: "Our new AI technology automatically selects the best photos from your event, saving photographers hours of manual curation work.",
          gr: "Η νεα μας τεχνολογια AI επιλεγει αυτοματα τις καλυτερες φωτογραφιες της εκδηλωσης σας, εξοικονομωντας ωρες χειροκινητης επιμελειας.",
        },
      },
      {
        date: "Dec 28, 2025",
        title: {
          en: "How Event Photographers Are Embracing Real-Time Streaming",
          gr: "Πως οι φωτογραφοι εκδηλωσεων υιοθετουν το realtime streaming",
        },
        excerpt: {
          en: "A deep dive into the growing trend of instant photo delivery at weddings, corporate events, and concerts.",
          gr: "Μια βαθια ματια στην αυξανομενη ταση αμεσης παραδοσης φωτογραφιων σε γαμους, εταιρικες εκδηλωσεις και συναυλιες.",
        },
      },
      {
        date: "Dec 10, 2025",
        title: {
          en: "nikofly Partners with Major Camera Manufacturers",
          gr: "Το nikofly συνεργαζεται με μεγαλους κατασκευαστες καμερων",
        },
        excerpt: {
          en: "New partnerships enable seamless integration with Canon, Nikon, and Sony cameras for enhanced workflow efficiency.",
          gr: "Νεες συνεργασιες επιτρεπουν ομαλη ενσωματωση με καμερες Canon, Nikon και Sony για ακομη καλυτερη ροη εργασιας.",
        },
      },
    ],
  },
  finalCta: {
    heading: { en: "What are you waiting for?", gr: "Τι περιμενετε;" },
    description: { en: "Download now for an excellent experience", gr: "Κατεβαστε τωρα για εξαιρετικη εμπειρια" },
    appStoreText: { en: "Download on App Store", gr: "Ληψη στο App Store" },
    playStoreText: { en: "Get it on Google Play", gr: "Ληψη στο Google Play" },
  },
  footer: {
    description: {
      en: "The event live streaming photos solution that lets photographers & guests enjoy photos instantly.",
      gr: "Η λυση ζωντανης μεταδοσης φωτογραφιων εκδηλωσεων που επιτρεπει σε φωτογραφους και καλεσμενους να απολαμβανουν φωτογραφιες αμεσα.",
    },
    featuresHeading: { en: "Features", gr: "Δυνατοτητες" },
    companyHeading: { en: "Company", gr: "Εταιρεια" },
    contactHeading: { en: "Contact", gr: "Επικοινωνια" },
    copyrightText: { en: "© 2026 nikofly. All rights reserved.", gr: "© 2026 nikofly. Ολα τα δικαιωματα διατηρουνται." },
    featuresLinks: [
      { label: { en: "Real-Time Transfer", gr: "Realtime μεταφορα" }, href: "#" },
      { label: { en: "AI Selection", gr: "Επιλογη AI" }, href: "#" },
      { label: { en: "Cloud Storage", gr: "Cloud αποθηκευση" }, href: "#" },
      { label: { en: "API Access", gr: "Προσβαση API" }, href: "#" },
      { label: { en: "Integrations", gr: "Ενσωματωσεις" }, href: "#" },
    ],
    companyLinks: [
      { label: { en: "About Us", gr: "Σχετικα με εμας" }, href: "#" },
      { label: { en: "Careers", gr: "Καριερα" }, href: "#" },
      { label: { en: "Press", gr: "Τυπος" }, href: "#" },
      { label: { en: "Blog", gr: "Blog" }, href: "#" },
      { label: { en: "Contact", gr: "Επικοινωνια" }, href: "#" },
    ],
    contactLinks: [
      { label: { en: "support@nikofly.app", gr: "support@nikofly.app" }, href: "mailto:support@nikofly.app" },
      { label: { en: "+1 (888) 123-4567", gr: "+1 (888) 123-4567" }, href: "tel:+18881234567" },
      { label: { en: "San Francisco, CA", gr: "San Francisco, CA" }, href: "#" },
    ],
    legalLinks: [
      { label: { en: "Terms of Service", gr: "Οροι χρησης" }, href: "#" },
      { label: { en: "Privacy Policy", gr: "Πολιτικη απορρητου" }, href: "#" },
      { label: { en: "Cookie Policy", gr: "Πολιτικη cookies" }, href: "#" },
    ],
  },
};

const isObject = (value: unknown): value is Record<string, unknown> =>
  !!value && typeof value === "object" && !Array.isArray(value);

export const mergeSiteSettings = (
  current: SiteSettings,
  incoming?: Partial<SiteSettings> | null,
): SiteSettings => {
  if (!incoming) return current;

  const merge = (base: any, next: any): any => {
    if (next === undefined) return base;
    if (Array.isArray(next)) return next;
    if (isObject(base) && isObject(next)) {
      const merged: Record<string, unknown> = { ...base };
      Object.entries(next).forEach(([key, value]) => {
        merged[key] = merge((base as Record<string, unknown>)[key], value);
      });
      return merged;
    }
    return next;
  };

  return merge(current, incoming) as SiteSettings;
};

export const getLocalizedText = (
  value: LocalizedText | undefined,
  language: LanguageCode,
) => value?.[language] ?? value?.en ?? "";
