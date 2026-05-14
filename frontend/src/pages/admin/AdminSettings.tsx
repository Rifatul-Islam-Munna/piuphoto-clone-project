import { ChangeEvent, Dispatch, SetStateAction, useEffect, useMemo, useRef, useState } from "react";
import { ImagePlus, Loader2, Save, Upload } from "lucide-react";
import { toast } from "sonner";
import AdminLayout from "./AdminLayout";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { PatchRequestAxios, PostRequestAxios } from "@/api-hooks/api-hooks";
import { useQueryWrapper } from "@/api-hooks/react-query-wrapper";
import { useQueryClient } from "@tanstack/react-query";
import {
  defaultSiteSettings,
  mergeSiteSettings,
  SiteSettings,
  SiteSettingsResponse,
} from "@/lib/site-settings";

type UploadResponse = {
  url?: string;
  message?: string;
};

const cloneSettings = (value: SiteSettings) =>
  JSON.parse(JSON.stringify(value)) as SiteSettings;

const sanitizeSettingsForSave = (value: SiteSettings) => {
  const next = JSON.parse(JSON.stringify(value)) as SiteSettings & {
    _id?: string;
    __v?: number;
    createdAt?: string;
    updatedAt?: string;
  };

  delete next._id;
  delete next.__v;
  delete next.createdAt;
  delete next.updatedAt;

  return next;
};

const lineJoin = (items: string[]) => items.join("\n");

const parseLines = (value: string) =>
  value
    .split("\n")
    .map((item) => item.trim())
    .filter(Boolean);

const localizedLinesValue = (items: Array<{ en: string; gr: string }>, language: "en" | "gr") =>
  items.map((item) => item[language] || "").join("\n");

const updateLocalizedLines = (
  current: Array<{ en: string; gr: string }>,
  language: "en" | "gr",
  value: string,
) => {
  const lines = parseLines(value);
  const size = Math.max(lines.length, current.length);
  return Array.from({ length: size }, (_, index) => ({
    en: language === "en" ? (lines[index] ?? "") : (current[index]?.en ?? ""),
    gr: language === "gr" ? (lines[index] ?? "") : (current[index]?.gr ?? ""),
  })).filter((item) => item.en || item.gr);
};

const linksToText = (items: Array<{ label: { en: string; gr: string }; href: string }>) =>
  items.map((item) => `${item.label.en}|${item.label.gr}|${item.href}`).join("\n");

const parseLinksText = (value: string) =>
  parseLines(value).map((line) => {
    const [en = "", gr = "", href = "#"] = line.split("|");
    return {
      label: { en: en.trim(), gr: gr.trim() },
      href: href.trim() || "#",
    };
  });

const updateNested = (
  setDraft: Dispatch<SetStateAction<SiteSettings>>,
  mutator: (next: SiteSettings) => void,
) => {
  setDraft((prev) => {
    const next = cloneSettings(prev);
    mutator(next);
    return next;
  });
};

const SectionTitle = ({
  title,
  description,
}: {
  title: string;
  description: string;
}) => (
  <div className="space-y-1">
    <h3 className="text-lg font-semibold">{title}</h3>
    <p className="text-sm text-muted-foreground">{description}</p>
  </div>
);

const LocalizedInput = ({
  label,
  value,
  onChange,
}: {
  label: string;
  value: { en: string; gr: string };
  onChange: (language: "en" | "gr", nextValue: string) => void;
}) => (
  <div className="grid gap-4 md:grid-cols-2">
    <div className="space-y-2">
      <Label>{label} (EN)</Label>
      <Input value={value.en} onChange={(event) => onChange("en", event.target.value)} />
    </div>
    <div className="space-y-2">
      <Label>{label} (GR)</Label>
      <Input value={value.gr} onChange={(event) => onChange("gr", event.target.value)} />
    </div>
  </div>
);

const LocalizedTextarea = ({
  label,
  value,
  onChange,
  rows = 3,
}: {
  label: string;
  value: { en: string; gr: string };
  onChange: (language: "en" | "gr", nextValue: string) => void;
  rows?: number;
}) => (
  <div className="grid gap-4 md:grid-cols-2">
    <div className="space-y-2">
      <Label>{label} (EN)</Label>
      <Textarea rows={rows} value={value.en} onChange={(event) => onChange("en", event.target.value)} />
    </div>
    <div className="space-y-2">
      <Label>{label} (GR)</Label>
      <Textarea rows={rows} value={value.gr} onChange={(event) => onChange("gr", event.target.value)} />
    </div>
  </div>
);

export default function AdminSettings() {
  const queryClient = useQueryClient();
  const [oldPassword, setOldPassword] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [savingPassword, setSavingPassword] = useState(false);
  const [savingSettings, setSavingSettings] = useState(false);
  const [uploadingLogo, setUploadingLogo] = useState(false);
  const [draft, setDraft] = useState<SiteSettings>(defaultSiteSettings);
  const initialized = useRef(false);
  const fileInputRef = useRef<HTMLInputElement | null>(null);

  const { data, isLoading } = useQueryWrapper<SiteSettingsResponse>(
    ["admin-site-settings"],
    "/settings/admin",
    { withToken: true, withCredentials: true },
  );

  useEffect(() => {
    if (!data?.data || initialized.current) return;
    setDraft(mergeSiteSettings(defaultSiteSettings, data.data));
    initialized.current = true;
  }, [data]);

  const updatePassword = async () => {
    setSavingPassword(true);
    const [response, error] = await PatchRequestAxios<{ message: string }>(
      "/user/update-password",
      { oldPassword, newPassword },
      { withToken: true, withCredentials: true },
    );
    setSavingPassword(false);

    if (error || !response) {
      toast.error(error?.message || "Failed to update password");
      return;
    }

    toast.success("Password updated");
    setOldPassword("");
    setNewPassword("");
  };

  const uploadLogo = async (event: ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    if (!file) return;

    const formData = new FormData();
    formData.append("file", file);
    setUploadingLogo(true);

    const [response, error] = await PostRequestAxios<UploadResponse>(
      "/image/upload",
      formData,
      {
        withToken: true,
        withCredentials: true,
        headers: { "Content-Type": "multipart/form-data" },
      },
    );

    setUploadingLogo(false);
    if (error || !response?.url) {
      toast.error(error?.message || "Failed to upload logo");
      return;
    }

    updateNested(setDraft, (next) => {
      next.site.logoUrl = response.url || "";
    });
    toast.success("Logo uploaded");
    event.target.value = "";
  };

  const saveSettings = async () => {
    setSavingSettings(true);
    const [response, error] = await PatchRequestAxios<SiteSettingsResponse>(
      "/settings/admin",
      sanitizeSettingsForSave(draft),
      { withToken: true, withCredentials: true },
    );
    setSavingSettings(false);

    if (error || !response?.data) {
      toast.error(error?.message || "Failed to save website settings");
      return;
    }

    setDraft(mergeSiteSettings(defaultSiteSettings, response.data));
    initialized.current = true;
    queryClient.invalidateQueries({ queryKey: ["admin-site-settings"] });
    queryClient.invalidateQueries({ queryKey: ["site-settings-public"] });
    toast.success("Website settings updated");
  };

  const featureCards = useMemo(() => draft.featuresGrid.items, [draft.featuresGrid.items]);

  return (
    <AdminLayout>
      <div className="mx-auto max-w-6xl space-y-6">
        <div>
          <h1 className="text-2xl font-bold">Settings</h1>
          <p className="text-muted-foreground">Manage admin security plus bilingual website content.</p>
        </div>

        <Card>
          <CardHeader>
            <CardTitle>Change Password</CardTitle>
            <CardDescription>Update password for current admin account.</CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="oldPassword">Current password</Label>
              <Input
                id="oldPassword"
                type="password"
                value={oldPassword}
                onChange={(event) => setOldPassword(event.target.value)}
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="newPassword">New password</Label>
              <Input
                id="newPassword"
                type="password"
                value={newPassword}
                onChange={(event) => setNewPassword(event.target.value)}
              />
            </div>
            <div className="flex justify-end">
              <Button onClick={updatePassword} disabled={savingPassword || !oldPassword || !newPassword}>
                {savingPassword ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : <Save className="mr-2 h-4 w-4" />}
                Save Password
              </Button>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Website Content</CardTitle>
            <CardDescription>
              Home page text uses EN and GR. Pricing section and addon cards stay unchanged.
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-10">
            {isLoading && !initialized.current ? (
              <div className="flex justify-center py-8">
                <Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
              </div>
            ) : (
              <>
                <div className="space-y-4">
                  <SectionTitle title="Site" description="Navbar brand, site title, favicon source." />
                  <div className="grid gap-4 md:grid-cols-[1fr_auto]">
                    <div className="space-y-2">
                      <Label>Site title</Label>
                      <Input
                        value={draft.site.title}
                        onChange={(event) => updateNested(setDraft, (next) => {
                          next.site.title = event.target.value;
                        })}
                      />
                    </div>
                    <div className="space-y-2">
                      <Label>Logo</Label>
                      <div className="flex items-center gap-3">
                        {draft.site.logoUrl ? (
                          <img src={draft.site.logoUrl} alt={draft.site.title} className="h-12 w-12 rounded-lg object-cover border" />
                        ) : (
                          <div className="h-12 w-12 rounded-lg border flex items-center justify-center">
                            <ImagePlus className="h-5 w-5 text-muted-foreground" />
                          </div>
                        )}
                        <div className="flex gap-2">
                          <Button type="button" variant="outline" onClick={() => fileInputRef.current?.click()} disabled={uploadingLogo}>
                            {uploadingLogo ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : <Upload className="mr-2 h-4 w-4" />}
                            Upload
                          </Button>
                          <Input
                            value={draft.site.logoUrl}
                            onChange={(event) => updateNested(setDraft, (next) => {
                              next.site.logoUrl = event.target.value;
                            })}
                            placeholder="https://..."
                            className="min-w-[260px]"
                          />
                        </div>
                        <input ref={fileInputRef} type="file" accept="image/*" className="hidden" onChange={uploadLogo} />
                      </div>
                    </div>
                  </div>
                </div>

                <div className="space-y-4">
                  <SectionTitle title="Navbar" description="One line per item: label EN | label GR | href" />
                  <Textarea
                    rows={8}
                    value={linksToText(draft.navbar.menuItems)}
                    onChange={(event) => updateNested(setDraft, (next) => {
                      next.navbar.menuItems = parseLinksText(event.target.value);
                    })}
                  />
                  <LocalizedInput
                    label="Login label"
                    value={draft.navbar.loginLabel}
                    onChange={(language, value) => updateNested(setDraft, (next) => {
                      next.navbar.loginLabel[language] = value;
                    })}
                  />
                  <LocalizedInput
                    label="Dashboard label"
                    value={draft.navbar.dashboardLabel}
                    onChange={(language, value) => updateNested(setDraft, (next) => {
                      next.navbar.dashboardLabel[language] = value;
                    })}
                  />
                  <LocalizedInput
                    label="Profile label"
                    value={draft.navbar.profileLabel}
                    onChange={(language, value) => updateNested(setDraft, (next) => {
                      next.navbar.profileLabel[language] = value;
                    })}
                  />
                  <LocalizedInput
                    label="Logout label"
                    value={draft.navbar.logoutLabel}
                    onChange={(language, value) => updateNested(setDraft, (next) => {
                      next.navbar.logoutLabel[language] = value;
                    })}
                  />
                </div>

                <div className="space-y-4">
                  <SectionTitle title="Hero" description="Main top section." />
                  <LocalizedInput
                    label="Title suffix"
                    value={draft.hero.titleSuffix}
                    onChange={(language, value) => updateNested(setDraft, (next) => {
                      next.hero.titleSuffix[language] = value;
                    })}
                  />
                  <LocalizedTextarea
                    label="Description"
                    value={draft.hero.description}
                    rows={3}
                    onChange={(language, value) => updateNested(setDraft, (next) => {
                      next.hero.description[language] = value;
                    })}
                  />
                  <LocalizedInput
                    label="App Store button"
                    value={draft.hero.appStoreText}
                    onChange={(language, value) => updateNested(setDraft, (next) => {
                      next.hero.appStoreText[language] = value;
                    })}
                  />
                  <LocalizedInput
                    label="Google Play button"
                    value={draft.hero.playStoreText}
                    onChange={(language, value) => updateNested(setDraft, (next) => {
                      next.hero.playStoreText[language] = value;
                    })}
                  />
                </div>

                <div className="space-y-4">
                  <SectionTitle title="Features Grid" description="Four cards. Keep variants as yellow, blue, purple, pink." />
                  {featureCards.map((feature, index) => (
                    <div key={index} className="rounded-lg border p-4 space-y-4">
                      <div className="grid gap-4 md:grid-cols-2">
                        <div className="space-y-2">
                          <Label>Icon</Label>
                          <Input
                            value={feature.icon}
                            onChange={(event) => updateNested(setDraft, (next) => {
                              next.featuresGrid.items[index].icon = event.target.value;
                            })}
                          />
                        </div>
                        <div className="space-y-2">
                          <Label>Variant</Label>
                          <Input
                            value={feature.variant}
                            onChange={(event) => updateNested(setDraft, (next) => {
                              next.featuresGrid.items[index].variant = event.target.value as "yellow" | "blue" | "purple" | "pink";
                            })}
                          />
                        </div>
                      </div>
                      <LocalizedInput
                        label={`Feature ${index + 1} title`}
                        value={feature.title}
                        onChange={(language, value) => updateNested(setDraft, (next) => {
                          next.featuresGrid.items[index].title[language] = value;
                        })}
                      />
                      <LocalizedTextarea
                        label={`Feature ${index + 1} description`}
                        value={feature.description}
                        onChange={(language, value) => updateNested(setDraft, (next) => {
                          next.featuresGrid.items[index].description[language] = value;
                        })}
                      />
                    </div>
                  ))}
                </div>

                <div className="space-y-4">
                  <SectionTitle title="Fly Photos" description="Mid page promo section." />
                  <LocalizedInput
                    label="Heading"
                    value={draft.flyPhotos.heading}
                    onChange={(language, value) => updateNested(setDraft, (next) => {
                      next.flyPhotos.heading[language] = value;
                    })}
                  />
                  <LocalizedTextarea
                    label="Description"
                    value={draft.flyPhotos.description}
                    onChange={(language, value) => updateNested(setDraft, (next) => {
                      next.flyPhotos.description[language] = value;
                    })}
                  />
                </div>

                <div className="space-y-4">
                  <SectionTitle title="Event Streaming" description="Chips and bullet lines use separate EN / GR line lists." />
                  <LocalizedInput
                    label="Heading"
                    value={draft.eventStreaming.heading}
                    onChange={(language, value) => updateNested(setDraft, (next) => {
                      next.eventStreaming.heading[language] = value;
                    })}
                  />
                  <LocalizedInput
                    label="CTA label"
                    value={draft.eventStreaming.ctaLabel}
                    onChange={(language, value) => updateNested(setDraft, (next) => {
                      next.eventStreaming.ctaLabel[language] = value;
                    })}
                  />
                  <div className="grid gap-4 md:grid-cols-2">
                    <div className="space-y-2">
                      <Label>Chips (EN, one per line)</Label>
                      <Textarea
                        rows={4}
                        value={localizedLinesValue(draft.eventStreaming.chips, "en")}
                        onChange={(event) => updateNested(setDraft, (next) => {
                          next.eventStreaming.chips = updateLocalizedLines(next.eventStreaming.chips, "en", event.target.value);
                        })}
                      />
                    </div>
                    <div className="space-y-2">
                      <Label>Chips (GR, one per line)</Label>
                      <Textarea
                        rows={4}
                        value={localizedLinesValue(draft.eventStreaming.chips, "gr")}
                        onChange={(event) => updateNested(setDraft, (next) => {
                          next.eventStreaming.chips = updateLocalizedLines(next.eventStreaming.chips, "gr", event.target.value);
                        })}
                      />
                    </div>
                  </div>
                  <div className="grid gap-4 md:grid-cols-2">
                    <div className="space-y-2">
                      <Label>Bullet items (EN)</Label>
                      <Textarea
                        rows={6}
                        value={localizedLinesValue(draft.eventStreaming.features, "en")}
                        onChange={(event) => updateNested(setDraft, (next) => {
                          next.eventStreaming.features = updateLocalizedLines(next.eventStreaming.features, "en", event.target.value);
                        })}
                      />
                    </div>
                    <div className="space-y-2">
                      <Label>Bullet items (GR)</Label>
                      <Textarea
                        rows={6}
                        value={localizedLinesValue(draft.eventStreaming.features, "gr")}
                        onChange={(event) => updateNested(setDraft, (next) => {
                          next.eventStreaming.features = updateLocalizedLines(next.eventStreaming.features, "gr", event.target.value);
                        })}
                      />
                    </div>
                  </div>
                </div>

                <div className="space-y-4">
                  <SectionTitle title="API Section" description="API section text and bullets." />
                  <LocalizedInput
                    label="Heading"
                    value={draft.apiSection.heading}
                    onChange={(language, value) => updateNested(setDraft, (next) => {
                      next.apiSection.heading[language] = value;
                    })}
                  />
                  <LocalizedTextarea
                    label="Description"
                    value={draft.apiSection.description}
                    onChange={(language, value) => updateNested(setDraft, (next) => {
                      next.apiSection.description[language] = value;
                    })}
                  />
                  <LocalizedTextarea
                    label="Card title"
                    value={draft.apiSection.cardTitle}
                    onChange={(language, value) => updateNested(setDraft, (next) => {
                      next.apiSection.cardTitle[language] = value;
                    })}
                  />
                  <div className="grid gap-4 md:grid-cols-2">
                    <div className="space-y-2">
                      <Label>API bullets (EN)</Label>
                      <Textarea
                        rows={6}
                        value={localizedLinesValue(draft.apiSection.features, "en")}
                        onChange={(event) => updateNested(setDraft, (next) => {
                          next.apiSection.features = updateLocalizedLines(next.apiSection.features, "en", event.target.value);
                        })}
                      />
                    </div>
                    <div className="space-y-2">
                      <Label>API bullets (GR)</Label>
                      <Textarea
                        rows={6}
                        value={localizedLinesValue(draft.apiSection.features, "gr")}
                        onChange={(event) => updateNested(setDraft, (next) => {
                          next.apiSection.features = updateLocalizedLines(next.apiSection.features, "gr", event.target.value);
                        })}
                      />
                    </div>
                  </div>
                </div>

                <div className="space-y-4">
                  <SectionTitle title="Connection Section" description="Wired / wireless cards." />
                  <LocalizedInput
                    label="Heading"
                    value={draft.connectionSection.heading}
                    onChange={(language, value) => updateNested(setDraft, (next) => {
                      next.connectionSection.heading[language] = value;
                    })}
                  />
                  <LocalizedTextarea
                    label="Description"
                    value={draft.connectionSection.description}
                    onChange={(language, value) => updateNested(setDraft, (next) => {
                      next.connectionSection.description[language] = value;
                    })}
                  />
                  <LocalizedInput
                    label="Wired title"
                    value={draft.connectionSection.wiredTitle}
                    onChange={(language, value) => updateNested(setDraft, (next) => {
                      next.connectionSection.wiredTitle[language] = value;
                    })}
                  />
                  <LocalizedTextarea
                    label="Wired description"
                    value={draft.connectionSection.wiredDescription}
                    onChange={(language, value) => updateNested(setDraft, (next) => {
                      next.connectionSection.wiredDescription[language] = value;
                    })}
                  />
                  <LocalizedInput
                    label="Wireless title"
                    value={draft.connectionSection.wirelessTitle}
                    onChange={(language, value) => updateNested(setDraft, (next) => {
                      next.connectionSection.wirelessTitle[language] = value;
                    })}
                  />
                  <LocalizedTextarea
                    label="Wireless description"
                    value={draft.connectionSection.wirelessDescription}
                    onChange={(language, value) => updateNested(setDraft, (next) => {
                      next.connectionSection.wirelessDescription[language] = value;
                    })}
                  />
                  <LocalizedInput
                    label="CTA label"
                    value={draft.connectionSection.ctaLabel}
                    onChange={(language, value) => updateNested(setDraft, (next) => {
                      next.connectionSection.ctaLabel[language] = value;
                    })}
                  />
                </div>

                <div className="space-y-4">
                  <SectionTitle title="Trusted Brands" description="Heading plus one brand name per line." />
                  <LocalizedInput
                    label="Heading"
                    value={draft.trustedBrands.heading}
                    onChange={(language, value) => updateNested(setDraft, (next) => {
                      next.trustedBrands.heading[language] = value;
                    })}
                  />
                  <div className="space-y-2">
                    <Label>Brands</Label>
                    <Textarea
                      rows={6}
                      value={lineJoin(draft.trustedBrands.brands)}
                      onChange={(event) => updateNested(setDraft, (next) => {
                        next.trustedBrands.brands = parseLines(event.target.value);
                      })}
                    />
                  </div>
                </div>

                <div className="space-y-4">
                  <SectionTitle title="Case Study" description="Quote card content." />
                  <LocalizedTextarea
                    label="Quote"
                    value={draft.caseStudy.quote}
                    rows={4}
                    onChange={(language, value) => updateNested(setDraft, (next) => {
                      next.caseStudy.quote[language] = value;
                    })}
                  />
                  <div className="grid gap-4 md:grid-cols-2">
                    <div className="space-y-2">
                      <Label>Name</Label>
                      <Input
                        value={draft.caseStudy.name}
                        onChange={(event) => updateNested(setDraft, (next) => {
                          next.caseStudy.name = event.target.value;
                        })}
                      />
                    </div>
                  </div>
                  <LocalizedInput
                    label="Role"
                    value={draft.caseStudy.title}
                    onChange={(language, value) => updateNested(setDraft, (next) => {
                      next.caseStudy.title[language] = value;
                    })}
                  />
                  <LocalizedInput
                    label="Company"
                    value={draft.caseStudy.company}
                    onChange={(language, value) => updateNested(setDraft, (next) => {
                      next.caseStudy.company[language] = value;
                    })}
                  />
                </div>

                <div className="space-y-4">
                  <SectionTitle title="Newsroom" description="Three cards. Dates stay plain text." />
                  <LocalizedInput
                    label="Heading"
                    value={draft.newsroom.heading}
                    onChange={(language, value) => updateNested(setDraft, (next) => {
                      next.newsroom.heading[language] = value;
                    })}
                  />
                  <LocalizedTextarea
                    label="Description"
                    value={draft.newsroom.description}
                    onChange={(language, value) => updateNested(setDraft, (next) => {
                      next.newsroom.description[language] = value;
                    })}
                  />
                  <LocalizedInput
                    label="Read more label"
                    value={draft.newsroom.readMoreLabel}
                    onChange={(language, value) => updateNested(setDraft, (next) => {
                      next.newsroom.readMoreLabel[language] = value;
                    })}
                  />
                  {draft.newsroom.items.map((item, index) => (
                    <div key={index} className="rounded-lg border p-4 space-y-4">
                      <div className="space-y-2">
                        <Label>Date</Label>
                        <Input
                          value={item.date}
                          onChange={(event) => updateNested(setDraft, (next) => {
                            next.newsroom.items[index].date = event.target.value;
                          })}
                        />
                      </div>
                      <LocalizedInput
                        label={`News ${index + 1} title`}
                        value={item.title}
                        onChange={(language, value) => updateNested(setDraft, (next) => {
                          next.newsroom.items[index].title[language] = value;
                        })}
                      />
                      <LocalizedTextarea
                        label={`News ${index + 1} excerpt`}
                        value={item.excerpt}
                        rows={4}
                        onChange={(language, value) => updateNested(setDraft, (next) => {
                          next.newsroom.items[index].excerpt[language] = value;
                        })}
                      />
                    </div>
                  ))}
                </div>

                <div className="space-y-4">
                  <SectionTitle title="Final CTA" description="Bottom call-to-action section." />
                  <LocalizedInput
                    label="Heading"
                    value={draft.finalCta.heading}
                    onChange={(language, value) => updateNested(setDraft, (next) => {
                      next.finalCta.heading[language] = value;
                    })}
                  />
                  <LocalizedTextarea
                    label="Description"
                    value={draft.finalCta.description}
                    onChange={(language, value) => updateNested(setDraft, (next) => {
                      next.finalCta.description[language] = value;
                    })}
                  />
                  <LocalizedInput
                    label="App Store button"
                    value={draft.finalCta.appStoreText}
                    onChange={(language, value) => updateNested(setDraft, (next) => {
                      next.finalCta.appStoreText[language] = value;
                    })}
                  />
                  <LocalizedInput
                    label="Google Play button"
                    value={draft.finalCta.playStoreText}
                    onChange={(language, value) => updateNested(setDraft, (next) => {
                      next.finalCta.playStoreText[language] = value;
                    })}
                  />
                </div>

                <div className="space-y-4">
                  <SectionTitle title="Footer" description="Links use one line: label EN | label GR | href" />
                  <LocalizedTextarea
                    label="Description"
                    value={draft.footer.description}
                    rows={3}
                    onChange={(language, value) => updateNested(setDraft, (next) => {
                      next.footer.description[language] = value;
                    })}
                  />
                  <LocalizedInput
                    label="Features heading"
                    value={draft.footer.featuresHeading}
                    onChange={(language, value) => updateNested(setDraft, (next) => {
                      next.footer.featuresHeading[language] = value;
                    })}
                  />
                  <LocalizedInput
                    label="Company heading"
                    value={draft.footer.companyHeading}
                    onChange={(language, value) => updateNested(setDraft, (next) => {
                      next.footer.companyHeading[language] = value;
                    })}
                  />
                  <LocalizedInput
                    label="Contact heading"
                    value={draft.footer.contactHeading}
                    onChange={(language, value) => updateNested(setDraft, (next) => {
                      next.footer.contactHeading[language] = value;
                    })}
                  />
                  <LocalizedInput
                    label="Copyright text"
                    value={draft.footer.copyrightText}
                    onChange={(language, value) => updateNested(setDraft, (next) => {
                      next.footer.copyrightText[language] = value;
                    })}
                  />
                  <div className="space-y-2">
                    <Label>Feature links</Label>
                    <Textarea
                      rows={6}
                      value={linksToText(draft.footer.featuresLinks)}
                      onChange={(event) => updateNested(setDraft, (next) => {
                        next.footer.featuresLinks = parseLinksText(event.target.value);
                      })}
                    />
                  </div>
                  <div className="space-y-2">
                    <Label>Company links</Label>
                    <Textarea
                      rows={6}
                      value={linksToText(draft.footer.companyLinks)}
                      onChange={(event) => updateNested(setDraft, (next) => {
                        next.footer.companyLinks = parseLinksText(event.target.value);
                      })}
                    />
                  </div>
                  <div className="space-y-2">
                    <Label>Contact links</Label>
                    <Textarea
                      rows={5}
                      value={linksToText(draft.footer.contactLinks)}
                      onChange={(event) => updateNested(setDraft, (next) => {
                        next.footer.contactLinks = parseLinksText(event.target.value);
                      })}
                    />
                  </div>
                  <div className="space-y-2">
                    <Label>Legal links</Label>
                    <Textarea
                      rows={5}
                      value={linksToText(draft.footer.legalLinks)}
                      onChange={(event) => updateNested(setDraft, (next) => {
                        next.footer.legalLinks = parseLinksText(event.target.value);
                      })}
                    />
                  </div>
                </div>

                <div className="flex justify-end">
                  <Button onClick={saveSettings} disabled={savingSettings}>
                    {savingSettings ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : <Save className="mr-2 h-4 w-4" />}
                    Save Website Settings
                  </Button>
                </div>
              </>
            )}
          </CardContent>
        </Card>
      </div>
    </AdminLayout>
  );
}
