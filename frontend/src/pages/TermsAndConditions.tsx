import Navbar from "@/components/landing/Navbar";
import Footer from "@/components/landing/Footer";
import { useSiteSettings } from "@/components/landing/site-settings-context";

export default function TermsAndConditions() {
  const { settings, t } = useSiteSettings();
  const pageLabel =
    settings.footer.legalLinks.find((item) => item.href === "/terms-and-conditions")?.label ??
    { en: "Terms and Conditions", gr: "Terms and Conditions" };

  return (
    <div className="min-h-screen flex flex-col">
      <Navbar />
      <main className="flex-1 pt-24 pb-16 px-6">
        <div className="container-custom max-w-4xl">
          <div className="mb-10">
            <h1 className="text-4xl font-bold text-foreground mb-4">
              {t(pageLabel)}
            </h1>
            <p className="text-muted-foreground">{settings.site.title}</p>
          </div>

          <div className="space-y-6">
            {settings.policy.termsAndConditions.map((item, index) => (
              <p key={index} className="text-base leading-8 text-foreground">
                {t(item)}
              </p>
            ))}
          </div>
        </div>
      </main>
      <Footer />
    </div>
  );
}
