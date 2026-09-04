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
  productShowcase: {
    imageUrl: string;
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
    cameraImageUrl: string;
    phoneImageUrl: string;
  };
  eventStreaming: {
    heading: LocalizedText;
    chips: LocalizedText[];
    ctaLabel: LocalizedText;
    phoneImageUrl: string;
    features: LocalizedText[];
  };
  apiSection: {
    heading: LocalizedText;
    description: LocalizedText;
    cardTitle: LocalizedText;
    imageUrl: string;
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
    imageUrl: string;
  };
  trustedBrands: {
    heading: LocalizedText;
    brands: string[];
  };
  caseStudy: {
    imageUrl: string;
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
      imageUrl: string;
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
  policy: {
    privacyPolicy: LocalizedText[];
    termsAndConditions: LocalizedText[];
  };
};

export type SiteSettingsResponse = {
  data: SiteSettings;
};

export const defaultSiteSettings: SiteSettings = {
  key: "website",
  site: {
    title: "airplex",
    logoUrl: "",
  },
  navbar: {
    menuItems: [
      { label: { en: "Try our event", gr: "Î”Î¿ÎºÎ¹Î¼Î±ÏƒÎµ Ï„Î·Î½ ÎµÎºÎ´Î·Î»Ï‰ÏƒÎ·" }, href: "#event" },
      { label: { en: "AI Magic", gr: "ÎœÎ±Î³ÎµÎ¹Î± AI" }, href: "#ai-magic" },
      { label: { en: "API", gr: "API" }, href: "#api" },
      { label: { en: "Connect & Transfer", gr: "Î£Ï…Î½Î´ÎµÏƒÎ· ÎºÎ±Î¹ Î¼ÎµÏ„Î±Ï†Î¿ÏÎ±" }, href: "#connect" },
      { label: { en: "Pricing", gr: "Î¤Î¹Î¼ÎµÏ‚" }, href: "/pricing" },
      { label: { en: "Case Studies", gr: "ÎœÎµÎ»ÎµÏ„ÎµÏ‚ Ï€ÎµÏÎ¹Ï€Ï„Ï‰ÏƒÎ·Ï‚" }, href: "#case-studies" },
      { label: { en: "Features", gr: "Î”Ï…Î½Î±Ï„Î¿Ï„Î·Ï„ÎµÏ‚" }, href: "#features" },
    ],
    loginLabel: { en: "Login", gr: "Î£Ï…Î½Î´ÎµÏƒÎ·" },
    dashboardLabel: { en: "Dashboard", gr: "Î Î¹Î½Î±ÎºÎ±Ï‚" },
    profileLabel: { en: "Profile", gr: "Î ÏÎ¿Ï†Î¹Î»" },
    logoutLabel: { en: "Logout", gr: "Î‘Ï€Î¿ÏƒÏ…Î½Î´ÎµÏƒÎ·" },
  },
  hero: {
    titleSuffix: { en: "Photos Can Fly", gr: "ÎŸÎ¹ Ï†Ï‰Ï„Î¿Î³ÏÎ±Ï†Î¹ÎµÏ‚ Î¼Ï€Î¿ÏÎ¿Ï…Î½ Î½Î± Ï€ÎµÏ„Î±Î¾Î¿Ï…Î½" },
    description: {
      en: "An event live streaming photos solution to let photographers & guests enjoy photos as easy as ABC",
      gr: "Î›Ï…ÏƒÎ· Î¶Ï‰Î½Ï„Î±Î½Î·Ï‚ Î¼ÎµÏ„Î±Î´Î¿ÏƒÎ·Ï‚ Ï†Ï‰Ï„Î¿Î³ÏÎ±Ï†Î¹Ï‰Î½ Î³Î¹Î± ÎµÎºÎ´Î·Î»Ï‰ÏƒÎµÎ¹Ï‚, Ï‰ÏƒÏ„Îµ Ï†Ï‰Ï„Î¿Î³ÏÎ±Ï†Î¿Î¹ ÎºÎ±Î¹ ÎºÎ±Î»ÎµÏƒÎ¼ÎµÎ½Î¿Î¹ Î½Î± Î±Ï€Î¿Î»Î±Î¼Î²Î±Î½Î¿Ï…Î½ Ï†Ï‰Ï„Î¿Î³ÏÎ±Ï†Î¹ÎµÏ‚ Ï€Î±Î½ÎµÏ…ÎºÎ¿Î»Î±",
    },
    appStoreText: { en: "Download on App Store", gr: "Î›Î·ÏˆÎ· ÏƒÏ„Î¿ App Store" },
    playStoreText: { en: "Get it on Google Play", gr: "Î›Î·ÏˆÎ· ÏƒÏ„Î¿ Google Play" },
  },
  productShowcase: {
    imageUrl: "",
  },
  featuresGrid: {
    items: [
      {
        icon: "ðŸ“±",
        variant: "yellow",
        title: { en: "Real-Time Photo Transfer", gr: "ÎœÎµÏ„Î±Ï†Î¿ÏÎ± Ï†Ï‰Ï„Î¿Î³ÏÎ±Ï†Î¹Ï‰Î½ ÏƒÎµ Ï€ÏÎ±Î³Î¼Î±Ï„Î¹ÎºÎ¿ Ï‡ÏÎ¿Î½Î¿" },
        description: { en: "Photos fly from camera to phone instantly", gr: "ÎŸÎ¹ Ï†Ï‰Ï„Î¿Î³ÏÎ±Ï†Î¹ÎµÏ‚ Ï€ÎµÏ„Î¿Ï…Î½ Î±Ï€Î¿ ÎºÎ±Î¼ÎµÏÎ± ÏƒÎµ ÎºÎ¹Î½Î·Ï„Î¿ Î±Î¼ÎµÏƒÎ±" },
      },
      {
        icon: "âš¡",
        variant: "blue",
        title: { en: "Lightning Fast", gr: "Î‘ÏƒÏ„ÏÎ±Ï€Î¹Î±Î¹Î± Ï„Î±Ï‡Ï…Ï„Î·Ï„Î±" },
        description: { en: "Upload speeds optimized for events", gr: "Î¤Î±Ï‡Ï…Ï„Î·Ï„ÎµÏ‚ Î±Î½ÎµÎ²Î±ÏƒÎ¼Î±Ï„Î¿Ï‚ Î²ÎµÎ»Ï„Î¹ÏƒÏ„Î¿Ï€Î¿Î¹Î·Î¼ÎµÎ½ÎµÏ‚ Î³Î¹Î± ÎµÎºÎ´Î·Î»Ï‰ÏƒÎµÎ¹Ï‚" },
      },
      {
        icon: "ðŸŽ¯",
        variant: "purple",
        title: { en: "Event-Based Sorting", gr: "Î¤Î±Î¾Î¹Î½Î¿Î¼Î·ÏƒÎ· Î±Î½Î± ÎµÎºÎ´Î·Î»Ï‰ÏƒÎ·" },
        description: { en: "Organize photos by event automatically", gr: "ÎŸÏÎ³Î±Î½Ï‰ÏƒÏ„Îµ Ï†Ï‰Ï„Î¿Î³ÏÎ±Ï†Î¹ÎµÏ‚ Î±Î½Î± ÎµÎºÎ´Î·Î»Ï‰ÏƒÎ· Î±Ï…Ï„Î¿Î¼Î±Ï„Î±" },
      },
      {
        icon: "ðŸ”’",
        variant: "pink",
        title: { en: "Secure & Private", gr: "Î‘ÏƒÏ†Î±Î»ÎµÏ‚ ÎºÎ±Î¹ Î¹Î´Î¹Ï‰Ï„Î¹ÎºÎ¿" },
        description: { en: "Enterprise-grade security for your photos", gr: "Î‘ÏƒÏ†Î±Î»ÎµÎ¹Î± ÎµÏ€Î¹Ï€ÎµÎ´Î¿Ï… enterprise Î³Î¹Î± Ï„Î¹Ï‚ Ï†Ï‰Ï„Î¿Î³ÏÎ±Ï†Î¹ÎµÏ‚ ÏƒÎ±Ï‚" },
      },
    ],
  },
  flyPhotos: {
    heading: { en: "Fly Your Photos Everywhere", gr: "Î£Ï„ÎµÎ¹Î»Ï„Îµ Ï„Î¹Ï‚ Ï†Ï‰Ï„Î¿Î³ÏÎ±Ï†Î¹ÎµÏ‚ ÏƒÎ±Ï‚ Ï€Î±Î½Ï„Î¿Ï…" },
    description: {
      en: "From camera to phone to social media - share your moments instantly",
      gr: "Î‘Ï€Î¿ Ï„Î·Î½ ÎºÎ±Î¼ÎµÏÎ± ÏƒÏ„Î¿ ÎºÎ¹Î½Î·Ï„Î¿ ÎºÎ±Î¹ ÏƒÏ„Î± social media - Î¼Î¿Î¹ÏÎ±ÏƒÏ„ÎµÎ¹Ï„Îµ Ï„Î¹Ï‚ ÏƒÏ„Î¹Î³Î¼ÎµÏ‚ ÏƒÎ±Ï‚ Î±Î¼ÎµÏƒÎ±",
    },
    cameraImageUrl: "",
    phoneImageUrl: "",
  },
  eventStreaming: {
    heading: {
      en: "Instant Event Streaming and Photo Organization",
      gr: "Î‘Î¼ÎµÏƒÎ· Î¼ÎµÏ„Î±Î´Î¿ÏƒÎ· ÎµÎºÎ´Î·Î»Ï‰ÏƒÎ·Ï‚ ÎºÎ±Î¹ Î¿ÏÎ³Î±Î½Ï‰ÏƒÎ· Ï†Ï‰Ï„Î¿Î³ÏÎ±Ï†Î¹Ï‰Î½",
    },
    chips: [
      { en: "AI Selection", gr: "Î•Ï€Î¹Î»Î¿Î³Î· AI" },
      { en: "AI Beautify", gr: "Î’ÎµÎ»Ï„Î¹Ï‰ÏƒÎ· AI" },
    ],
    ctaLabel: { en: "Get Started", gr: "ÎžÎµÎºÎ¹Î½Î·ÏƒÏ„Îµ" },
    phoneImageUrl: "",
    features: [
      { en: "AI-powered photo selection and curation", gr: "Î•Ï€Î¹Î»Î¿Î³Î· ÎºÎ±Î¹ ÎµÏ€Î¹Î¼ÎµÎ»ÎµÎ¹Î± Ï†Ï‰Ï„Î¿Î³ÏÎ±Ï†Î¹Ï‰Î½ Î¼Îµ AI" },
      { en: "Automatic enhancement and beautification", gr: "Î‘Ï…Ï„Î¿Î¼Î±Ï„Î· Î²ÎµÎ»Ï„Î¹Ï‰ÏƒÎ· ÎºÎ±Î¹ Î¿Î¼Î¿ÏÏ†Ï…Î½ÏƒÎ·" },
      { en: "Real-time streaming to all guests", gr: "Î–Ï‰Î½Ï„Î±Î½Î· Î¼ÎµÏ„Î±Î´Î¿ÏƒÎ· ÏƒÎµ Î¿Î»Î¿Ï…Ï‚ Ï„Î¿Ï…Ï‚ ÎºÎ±Î»ÎµÏƒÎ¼ÎµÎ½Î¿Ï…Ï‚" },
      { en: "Instant social media sharing", gr: "Î‘Î¼ÎµÏƒÎ¿ Î´Î¹Î±Î¼Î¿Î¹ÏÎ±ÏƒÎ¼Î¿ ÏƒÏ„Î± social media" },
      { en: "Cloud backup for all photos", gr: "Cloud backup Î³Î¹Î± Î¿Î»ÎµÏ‚ Ï„Î¹Ï‚ Ï†Ï‰Ï„Î¿Î³ÏÎ±Ï†Î¹ÎµÏ‚" },
    ],
  },
  apiSection: {
    heading: { en: "API Integration for Every Company", gr: "Î•Î½ÏƒÏ‰Î¼Î±Ï„Ï‰ÏƒÎ· API Î³Î¹Î± ÎºÎ±Î¸Îµ ÎµÏ„Î±Î¹ÏÎµÎ¹Î±" },
    description: {
      en: "Seamlessly integrate airplex into your existing workflow",
      gr: "Î•Î½ÏƒÏ‰Î¼Î±Ï„Ï‰ÏƒÏ„Îµ Ï„Î¿ airplex Î¿Î¼Î±Î»Î± ÏƒÏ„Î·Î½ Ï…Ï€Î±ÏÏ‡Î¿Ï…ÏƒÎ± ÏÎ¿Î· ÎµÏÎ³Î±ÏƒÎ¹Î±Ï‚ ÏƒÎ±Ï‚",
    },
    cardTitle: {
      en: "Integrate airplex in your product or website with ease",
      gr: "Î•Î½ÏƒÏ‰Î¼Î±Ï„Ï‰ÏƒÏ„Îµ Ï„Î¿ airplex ÏƒÏ„Î¿ Ï€ÏÎ¿ÏŠÎ¿Î½ Î® ÏƒÏ„Î·Î½ Î¹ÏƒÏ„Î¿ÏƒÎµÎ»Î¹Î´Î± ÏƒÎ±Ï‚ ÎµÏ…ÎºÎ¿Î»Î±",
    },
    imageUrl: "",
    features: [
      { en: "Simple REST API with comprehensive documentation", gr: "Î‘Ï€Î»Î¿ REST API Î¼Îµ Ï€Î»Î·ÏÎ· Ï„ÎµÎºÎ¼Î·ÏÎ¹Ï‰ÏƒÎ·" },
      { en: "Real-time webhooks for instant updates", gr: "Realtime webhooks Î³Î¹Î± Î±Î¼ÎµÏƒÎµÏ‚ ÎµÎ½Î·Î¼ÎµÏÏ‰ÏƒÎµÎ¹Ï‚" },
      { en: "SDKs for all major platforms", gr: "SDKs Î³Î¹Î± Î¿Î»ÎµÏ‚ Ï„Î¹Ï‚ Î²Î±ÏƒÎ¹ÎºÎµÏ‚ Ï€Î»Î±Ï„Ï†Î¿ÏÎ¼ÎµÏ‚" },
      { en: "99.9% uptime SLA guarantee", gr: "Î•Î³Î³Ï…Î·ÏƒÎ· SLA 99.9% uptime" },
    ],
  },
  connectionSection: {
    heading: { en: "Plug & Play or Go Wireless", gr: "Î£Ï…Î½Î´ÎµÏƒÏ„Îµ Î±Î¼ÎµÏƒÎ± Î® Î±ÏƒÏ…ÏÎ¼Î±Ï„Î±" },
    description: {
      en: "Connect your camera to your phone in seconds - wired or wireless",
      gr: "Î£Ï…Î½Î´ÎµÏƒÏ„Îµ Ï„Î·Î½ ÎºÎ±Î¼ÎµÏÎ± ÏƒÎ±Ï‚ Î¼Îµ Ï„Î¿ ÎºÎ¹Î½Î·Ï„Î¿ ÏƒÎµ Î´ÎµÏ…Ï„ÎµÏÎ¿Î»ÎµÏ€Ï„Î± - ÎµÎ½ÏƒÏ…ÏÎ¼Î±Ï„Î± Î® Î±ÏƒÏ…ÏÎ¼Î±Ï„Î±",
    },
    wiredTitle: { en: "Wired (OTG Cable)", gr: "Î•Î½ÏƒÏ…ÏÎ¼Î±Ï„Î± (ÎºÎ±Î»Ï‰Î´Î¹Î¿ OTG)" },
    wiredDescription: {
      en: "Connect directly with an OTG cable for the fastest, most reliable transfer speeds",
      gr: "Î£Ï…Î½Î´ÎµÎ¸ÎµÎ¹Ï„Îµ Î±Ï€ÎµÏ…Î¸ÎµÎ¹Î±Ï‚ Î¼Îµ ÎºÎ±Î»Ï‰Î´Î¹Î¿ OTG Î³Î¹Î± Ï„Î·Î½ Ï€Î¹Î¿ Î³ÏÎ·Î³Î¿ÏÎ· ÎºÎ±Î¹ Î±Î¾Î¹Î¿Ï€Î¹ÏƒÏ„Î· Î¼ÎµÏ„Î±Ï†Î¿ÏÎ±",
    },
    wirelessTitle: { en: "Wireless (FTP)", gr: "Î‘ÏƒÏ…ÏÎ¼Î±Ï„Î± (FTP)" },
    wirelessDescription: {
      en: "Go cable-free with FTP connection for ultimate flexibility during events",
      gr: "Î§Ï‰ÏÎ¹Ï‚ ÎºÎ±Î»Ï‰Î´Î¹Î± Î¼Îµ ÏƒÏ…Î½Î´ÎµÏƒÎ· FTP Î³Î¹Î± Î¼ÎµÎ³Î¹ÏƒÏ„Î· ÎµÏ…ÎµÎ»Î¹Î¾Î¹Î± ÏƒÏ„Î¹Ï‚ ÎµÎºÎ´Î·Î»Ï‰ÏƒÎµÎ¹Ï‚",
    },
    ctaLabel: { en: "Get Started", gr: "ÎžÎµÎºÎ¹Î½Î·ÏƒÏ„Îµ" },
    imageUrl: "",
  },
  trustedBrands: {
    heading: { en: "Trusted by Top Brands", gr: "Î•Î¼Ï€Î¹ÏƒÏ„Î¿ÏƒÏ…Î½Î· Î±Ï€Î¿ ÎºÎ¿ÏÏ…Ï†Î±Î¹Î± brands" },
    brands: [
      "Canon", "Nikon", "Sony", "Adobe", "Capture One", "Lightroom",
      "DJI", "GoPro", "Leica", "Fujifilm", "Olympus", "Panasonic",
      "Hasselblad", "Phase One", "Sigma", "Tamron", "Profoto", "Godox",
      "Peak Design", "Think Tank", "Lowepro", "Manfrotto", "SanDisk", "Lexar",
    ],
  },
  caseStudy: {
    imageUrl: "",
    quote: {
      en: "airplex transformed how we deliver wedding photos. Guests can now see and share their photos in real-time, creating an unforgettable experience. Our client satisfaction has never been higher.",
      gr: "Î¤Î¿ airplex Î¼ÎµÏ„Î±Î¼Î¿ÏÏ†Ï‰ÏƒÎµ Ï„Î¿Î½ Ï„ÏÎ¿Ï€Î¿ Ï€Î¿Ï… Ï€Î±ÏÎ±Î´Î¹Î´Î¿Ï…Î¼Îµ Ï†Ï‰Ï„Î¿Î³ÏÎ±Ï†Î¹ÎµÏ‚ Î³Î±Î¼Î¿Ï…. ÎŸÎ¹ ÎºÎ±Î»ÎµÏƒÎ¼ÎµÎ½Î¿Î¹ Î¼Ï€Î¿ÏÎ¿Ï…Î½ Ï„Ï‰ÏÎ± Î½Î± Î²Î»ÎµÏ€Î¿Ï…Î½ ÎºÎ±Î¹ Î½Î± Î¼Î¿Î¹ÏÎ±Î¶Î¿Î½Ï„Î±Î¹ Ï†Ï‰Ï„Î¿Î³ÏÎ±Ï†Î¹ÎµÏ‚ ÏƒÎµ Ï€ÏÎ±Î³Î¼Î±Ï„Î¹ÎºÎ¿ Ï‡ÏÎ¿Î½Î¿, Î´Î·Î¼Î¹Î¿Ï…ÏÎ³Ï‰Î½Ï„Î±Ï‚ Î±Î¾Î­Ï‡Î±ÏƒÏ„Î· ÎµÎ¼Ï€ÎµÎ¹ÏÎ¹Î±. Î— Î¹ÎºÎ±Î½Î¿Ï€Î¿Î¹Î·ÏƒÎ· Ï„Ï‰Î½ Ï€ÎµÎ»Î±Ï„Ï‰Î½ Î¼Î±Ï‚ Î´ÎµÎ½ Î·Ï„Î±Î½ Ï€Î¿Ï„Îµ Ï…ÏˆÎ·Î»Î¿Ï„ÎµÏÎ·.",
    },
    name: "Sarah Chen",
    title: { en: "Lead Photographer", gr: "Î•Ï€Î¹ÎºÎµÏ†Î±Î»Î·Ï‚ Ï†Ï‰Ï„Î¿Î³ÏÎ±Ï†Î¿Ï‚" },
    company: { en: "Eternal Moments Photography", gr: "Eternal Moments Photography" },
  },
  newsroom: {
    heading: { en: "Newsroom", gr: "ÎÎµÎ±" },
    description: { en: "Stay updated with the latest from airplex", gr: "ÎœÎµÎ¹Î½ÎµÏ„Îµ ÎµÎ½Î·Î¼ÎµÏÏ‰Î¼ÎµÎ½Î¿Î¹ Î¼Îµ Ï„Î± Î½ÎµÎ± Ï„Î¿Ï… airplex" },
    readMoreLabel: { en: "Read more", gr: "Î”Î¹Î±Î²Î±ÏƒÏ„Îµ Ï€ÎµÏÎ¹ÏƒÏƒÎ¿Ï„ÎµÏÎ±" },
    items: [
      {
        date: "Jan 15, 2026",
        imageUrl: "",
        title: {
          en: "airplex Launches AI-Powered Photo Selection Feature",
          gr: "Î¤Î¿ airplex Î»Î±Î½ÏƒÎ±ÏÎµÎ¹ Î´Ï…Î½Î±Ï„Î¿Ï„Î·Ï„Î± ÎµÏ€Î¹Î»Î¿Î³Î·Ï‚ Ï†Ï‰Ï„Î¿Î³ÏÎ±Ï†Î¹Ï‰Î½ Î¼Îµ AI",
        },
        excerpt: {
          en: "Our new AI technology automatically selects the best photos from your event, saving photographers hours of manual curation work.",
          gr: "Î— Î½ÎµÎ± Î¼Î±Ï‚ Ï„ÎµÏ‡Î½Î¿Î»Î¿Î³Î¹Î± AI ÎµÏ€Î¹Î»ÎµÎ³ÎµÎ¹ Î±Ï…Ï„Î¿Î¼Î±Ï„Î± Ï„Î¹Ï‚ ÎºÎ±Î»Ï…Ï„ÎµÏÎµÏ‚ Ï†Ï‰Ï„Î¿Î³ÏÎ±Ï†Î¹ÎµÏ‚ Ï„Î·Ï‚ ÎµÎºÎ´Î·Î»Ï‰ÏƒÎ·Ï‚ ÏƒÎ±Ï‚, ÎµÎ¾Î¿Î¹ÎºÎ¿Î½Î¿Î¼Ï‰Î½Ï„Î±Ï‚ Ï‰ÏÎµÏ‚ Ï‡ÎµÎ¹ÏÎ¿ÎºÎ¹Î½Î·Ï„Î·Ï‚ ÎµÏ€Î¹Î¼ÎµÎ»ÎµÎ¹Î±Ï‚.",
        },
      },
      {
        date: "Dec 28, 2025",
        imageUrl: "",
        title: {
          en: "How Event Photographers Are Embracing Real-Time Streaming",
          gr: "Î Ï‰Ï‚ Î¿Î¹ Ï†Ï‰Ï„Î¿Î³ÏÎ±Ï†Î¿Î¹ ÎµÎºÎ´Î·Î»Ï‰ÏƒÎµÏ‰Î½ Ï…Î¹Î¿Î¸ÎµÏ„Î¿Ï…Î½ Ï„Î¿ realtime streaming",
        },
        excerpt: {
          en: "A deep dive into the growing trend of instant photo delivery at weddings, corporate events, and concerts.",
          gr: "ÎœÎ¹Î± Î²Î±Î¸Î¹Î± Î¼Î±Ï„Î¹Î± ÏƒÏ„Î·Î½ Î±Ï…Î¾Î±Î½Î¿Î¼ÎµÎ½Î· Ï„Î±ÏƒÎ· Î±Î¼ÎµÏƒÎ·Ï‚ Ï€Î±ÏÎ±Î´Î¿ÏƒÎ·Ï‚ Ï†Ï‰Ï„Î¿Î³ÏÎ±Ï†Î¹Ï‰Î½ ÏƒÎµ Î³Î±Î¼Î¿Ï…Ï‚, ÎµÏ„Î±Î¹ÏÎ¹ÎºÎµÏ‚ ÎµÎºÎ´Î·Î»Ï‰ÏƒÎµÎ¹Ï‚ ÎºÎ±Î¹ ÏƒÏ…Î½Î±Ï…Î»Î¹ÎµÏ‚.",
        },
      },
      {
        date: "Dec 10, 2025",
        imageUrl: "",
        title: {
          en: "airplex Partners with Major Camera Manufacturers",
          gr: "Î¤Î¿ airplex ÏƒÏ…Î½ÎµÏÎ³Î±Î¶ÎµÏ„Î±Î¹ Î¼Îµ Î¼ÎµÎ³Î±Î»Î¿Ï…Ï‚ ÎºÎ±Ï„Î±ÏƒÎºÎµÏ…Î±ÏƒÏ„ÎµÏ‚ ÎºÎ±Î¼ÎµÏÏ‰Î½",
        },
        excerpt: {
          en: "New partnerships enable seamless integration with Canon, Nikon, and Sony cameras for enhanced workflow efficiency.",
          gr: "ÎÎµÎµÏ‚ ÏƒÏ…Î½ÎµÏÎ³Î±ÏƒÎ¹ÎµÏ‚ ÎµÏ€Î¹Ï„ÏÎµÏ€Î¿Ï…Î½ Î¿Î¼Î±Î»Î· ÎµÎ½ÏƒÏ‰Î¼Î±Ï„Ï‰ÏƒÎ· Î¼Îµ ÎºÎ±Î¼ÎµÏÎµÏ‚ Canon, Nikon ÎºÎ±Î¹ Sony Î³Î¹Î± Î±ÎºÎ¿Î¼Î· ÎºÎ±Î»Ï…Ï„ÎµÏÎ· ÏÎ¿Î· ÎµÏÎ³Î±ÏƒÎ¹Î±Ï‚.",
        },
      },
    ],
  },
  finalCta: {
    heading: { en: "What are you waiting for?", gr: "Î¤Î¹ Ï€ÎµÏÎ¹Î¼ÎµÎ½ÎµÏ„Îµ;" },
    description: { en: "Download now for an excellent experience", gr: "ÎšÎ±Ï„ÎµÎ²Î±ÏƒÏ„Îµ Ï„Ï‰ÏÎ± Î³Î¹Î± ÎµÎ¾Î±Î¹ÏÎµÏ„Î¹ÎºÎ· ÎµÎ¼Ï€ÎµÎ¹ÏÎ¹Î±" },
    appStoreText: { en: "Download on App Store", gr: "Î›Î·ÏˆÎ· ÏƒÏ„Î¿ App Store" },
    playStoreText: { en: "Get it on Google Play", gr: "Î›Î·ÏˆÎ· ÏƒÏ„Î¿ Google Play" },
  },
  footer: {
    description: {
      en: "The event live streaming photos solution that lets photographers & guests enjoy photos instantly.",
      gr: "Î— Î»Ï…ÏƒÎ· Î¶Ï‰Î½Ï„Î±Î½Î·Ï‚ Î¼ÎµÏ„Î±Î´Î¿ÏƒÎ·Ï‚ Ï†Ï‰Ï„Î¿Î³ÏÎ±Ï†Î¹Ï‰Î½ ÎµÎºÎ´Î·Î»Ï‰ÏƒÎµÏ‰Î½ Ï€Î¿Ï… ÎµÏ€Î¹Ï„ÏÎµÏ€ÎµÎ¹ ÏƒÎµ Ï†Ï‰Ï„Î¿Î³ÏÎ±Ï†Î¿Ï…Ï‚ ÎºÎ±Î¹ ÎºÎ±Î»ÎµÏƒÎ¼ÎµÎ½Î¿Ï…Ï‚ Î½Î± Î±Ï€Î¿Î»Î±Î¼Î²Î±Î½Î¿Ï…Î½ Ï†Ï‰Ï„Î¿Î³ÏÎ±Ï†Î¹ÎµÏ‚ Î±Î¼ÎµÏƒÎ±.",
    },
    featuresHeading: { en: "Features", gr: "Î”Ï…Î½Î±Ï„Î¿Ï„Î·Ï„ÎµÏ‚" },
    companyHeading: { en: "Company", gr: "Î•Ï„Î±Î¹ÏÎµÎ¹Î±" },
    contactHeading: { en: "Contact", gr: "Î•Ï€Î¹ÎºÎ¿Î¹Î½Ï‰Î½Î¹Î±" },
    copyrightText: { en: "Â© 2026 airplex. All rights reserved.", gr: "Â© 2026 airplex. ÎŸÎ»Î± Ï„Î± Î´Î¹ÎºÎ±Î¹Ï‰Î¼Î±Ï„Î± Î´Î¹Î±Ï„Î·ÏÎ¿Ï…Î½Ï„Î±Î¹." },
    featuresLinks: [
      { label: { en: "Real-Time Transfer", gr: "Realtime Î¼ÎµÏ„Î±Ï†Î¿ÏÎ±" }, href: "#" },
      { label: { en: "AI Selection", gr: "Î•Ï€Î¹Î»Î¿Î³Î· AI" }, href: "#" },
      { label: { en: "Cloud Storage", gr: "Cloud Î±Ï€Î¿Î¸Î·ÎºÎµÏ…ÏƒÎ·" }, href: "#" },
      { label: { en: "API Access", gr: "Î ÏÎ¿ÏƒÎ²Î±ÏƒÎ· API" }, href: "#" },
      { label: { en: "Integrations", gr: "Î•Î½ÏƒÏ‰Î¼Î±Ï„Ï‰ÏƒÎµÎ¹Ï‚" }, href: "#" },
    ],
    companyLinks: [
      { label: { en: "About Us", gr: "Î£Ï‡ÎµÏ„Î¹ÎºÎ± Î¼Îµ ÎµÎ¼Î±Ï‚" }, href: "#" },
      { label: { en: "Careers", gr: "ÎšÎ±ÏÎ¹ÎµÏÎ±" }, href: "#" },
      { label: { en: "Press", gr: "Î¤Ï…Ï€Î¿Ï‚" }, href: "#" },
      { label: { en: "Blog", gr: "Blog" }, href: "#" },
      { label: { en: "Contact", gr: "Î•Ï€Î¹ÎºÎ¿Î¹Î½Ï‰Î½Î¹Î±" }, href: "#" },
    ],
    contactLinks: [
      { label: { en: "support@airplex.app", gr: "support@airplex.app" }, href: "mailto:support@airplex.app" },
      { label: { en: "+1 (888) 123-4567", gr: "+1 (888) 123-4567" }, href: "tel:+18881234567" },
      { label: { en: "San Francisco, CA", gr: "San Francisco, CA" }, href: "#" },
    ],
    legalLinks: [
      { label: { en: "Terms and Conditions", gr: "ÎŸÏÎ¿Î¹ ÎºÎ±Î¹ Ï€ÏÎ¿Ï‹Ï€Î¿Î¸ÎµÏƒÎµÎ¹Ï‚" }, href: "/terms-and-conditions" },
      { label: { en: "Privacy Policy", gr: "Î Î¿Î»Î¹Ï„Î¹ÎºÎ· Î±Ï€Î¿ÏÏÎ·Ï„Î¿Ï…" }, href: "/privacy-policy" },
      { label: { en: "Cookie Policy", gr: "Î Î¿Î»Î¹Ï„Î¹ÎºÎ· cookies" }, href: "#" },
    ],
  },
  policy: {
    privacyPolicy: [
      {
        en: "We collect account, usage, and uploaded content data needed to operate airplex services.",
        gr: "Î£Ï…Î»Î»ÎµÎ³Î¿Ï…Î¼Îµ ÏƒÏ„Î¿Î¹Ï‡ÎµÎ¹Î± Î»Î¿Î³Î±ÏÎ¹Î±ÏƒÎ¼Î¿Ï…, Ï‡ÏÎ·ÏƒÎ·Ï‚ ÎºÎ±Î¹ Î±Î½ÎµÎ²Î±ÏƒÎ¼ÎµÎ½Î¿Ï… Ï€ÎµÏÎ¹ÎµÏ‡Î¿Î¼ÎµÎ½Î¿Ï… Ï€Î¿Ï… Î±Ï€Î±Î¹Ï„Î¿Ï…Î½Ï„Î±Î¹ Î³Î¹Î± Ï„Î· Î»ÎµÎ¹Ï„Î¿Ï…ÏÎ³Î¹Î± Ï„Î¿Ï… airplex.",
      },
      {
        en: "We use your data to deliver photo streaming, account access, billing, support, and security.",
        gr: "Î§ÏÎ·ÏƒÎ¹Î¼Î¿Ï€Î¿Î¹Î¿Ï…Î¼Îµ Ï„Î± Î´ÎµÎ´Î¿Î¼ÎµÎ½Î± ÏƒÎ±Ï‚ Î³Î¹Î± photo streaming, Ï€ÏÎ¿ÏƒÎ²Î±ÏƒÎ· Î»Î¿Î³Î±ÏÎ¹Î±ÏƒÎ¼Î¿Ï…, Ï‡ÏÎµÏ‰ÏƒÎ·, Ï…Ï€Î¿ÏƒÏ„Î·ÏÎ¹Î¾Î· ÎºÎ±Î¹ Î±ÏƒÏ†Î±Î»ÎµÎ¹Î±.",
      },
      {
        en: "We do not sell personal information. We may share data with infrastructure, payment, and storage providers only as needed to run the service.",
        gr: "Î”ÎµÎ½ Ï€Î¿Ï…Î»Î±Î¼Îµ Ï€ÏÎ¿ÏƒÏ‰Ï€Î¹ÎºÎ± Î´ÎµÎ´Î¿Î¼ÎµÎ½Î±. Î•Î½Î´ÎµÏ‡ÎµÏ„Î±Î¹ Î½Î± Î¼Î¿Î¹ÏÎ±Î¶Î¿Î¼Î±ÏƒÏ„Îµ Î´ÎµÎ´Î¿Î¼ÎµÎ½Î± Î¼Îµ Ï€Î±ÏÎ¿Ï‡Î¿Ï…Ï‚ Ï…Ï€Î¿Î´Î¿Î¼Î·Ï‚, Ï€Î»Î·ÏÏ‰Î¼Ï‰Î½ ÎºÎ±Î¹ Î±Ï€Î¿Î¸Î·ÎºÎµÏ…ÏƒÎ·Ï‚ Î¼Î¿Î½Î¿ Î¿Ï€Î¿Ï… Î±Ï€Î±Î¹Ï„ÎµÎ¹Ï„Î±Î¹ Î³Î¹Î± Ï„Î· Î»ÎµÎ¹Ï„Î¿Ï…ÏÎ³Î¹Î± Ï„Î·Ï‚ Ï…Ï€Î·ÏÎµÏƒÎ¹Î±Ï‚.",
      },
    ],
    termsAndConditions: [
      {
        en: "By using airplex, you agree to use the service lawfully and only for content you own or are authorized to manage.",
        gr: "Î§ÏÎ·ÏƒÎ¹Î¼Î¿Ï€Î¿Î¹Ï‰Î½Ï„Î±Ï‚ Ï„Î¿ airplex, ÏƒÏ…Î¼Ï†Ï‰Î½ÎµÎ¹Ï„Îµ Î½Î± Ï‡ÏÎ·ÏƒÎ¹Î¼Î¿Ï€Î¿Î¹ÎµÎ¹Ï„Îµ Ï„Î·Î½ Ï…Ï€Î·ÏÎµÏƒÎ¹Î± Î½Î¿Î¼Î¹Î¼Î± ÎºÎ±Î¹ Î¼Î¿Î½Î¿ Î³Î¹Î± Ï€ÎµÏÎ¹ÎµÏ‡Î¿Î¼ÎµÎ½Î¿ Ï€Î¿Ï… ÎºÎ±Ï„ÎµÏ‡ÎµÏ„Îµ Î® ÎµÏ‡ÎµÏ„Îµ Î±Î´ÎµÎ¹Î± Î½Î± Î´Î¹Î±Ï‡ÎµÎ¹ÏÎ¹Î¶ÎµÏƒÏ„Îµ.",
      },
      {
        en: "You are responsible for account security, uploaded content, and activity performed through your account.",
        gr: "Î•Î¹ÏƒÏ„Îµ Ï…Ï€ÎµÏ…Î¸Ï…Î½Î¿Î¹ Î³Î¹Î± Ï„Î·Î½ Î±ÏƒÏ†Î±Î»ÎµÎ¹Î± Ï„Î¿Ï… Î»Î¿Î³Î±ÏÎ¹Î±ÏƒÎ¼Î¿Ï…, Ï„Î¿ Î±Î½ÎµÎ²Î±ÏƒÎ¼ÎµÎ½Î¿ Ï€ÎµÏÎ¹ÎµÏ‡Î¿Î¼ÎµÎ½Î¿ ÎºÎ±Î¹ ÎºÎ±Î¸Îµ ÎµÎ½ÎµÏÎ³ÎµÎ¹Î± Ï€Î¿Ï… Î³Î¹Î½ÎµÏ„Î±Î¹ Î¼ÎµÏƒÏ‰ Ï„Î¿Ï… Î»Î¿Î³Î±ÏÎ¹Î±ÏƒÎ¼Î¿Ï… ÏƒÎ±Ï‚.",
      },
      {
        en: "We may suspend or terminate access for abuse, illegal activity, non-payment, or violations of platform rules.",
        gr: "ÎœÏ€Î¿ÏÎ¿Ï…Î¼Îµ Î½Î± Î±Î½Î±ÏƒÏ„ÎµÎ¹Î»Î¿Ï…Î¼Îµ Î® Î½Î± Ï„ÎµÏÎ¼Î±Ï„Î¹ÏƒÎ¿Ï…Î¼Îµ Ï„Î·Î½ Ï€ÏÎ¿ÏƒÎ²Î±ÏƒÎ· Î³Î¹Î± ÎºÎ±Ï„Î±Ï‡ÏÎ·ÏƒÎ·, Ï€Î±ÏÎ±Î½Î¿Î¼Î· Î´ÏÎ±ÏƒÏ„Î·ÏÎ¹Î¿Ï„Î·Ï„Î±, Î¼Î· Ï€Î»Î·ÏÏ‰Î¼Î· Î® Ï€Î±ÏÎ±Î²Î¹Î±ÏƒÎ· Ï„Ï‰Î½ ÎºÎ±Î½Î¿Î½Ï‰Î½ Ï„Î·Ï‚ Ï€Î»Î±Ï„Ï†Î¿ÏÎ¼Î±Ï‚.",
      },
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

