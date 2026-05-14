import { Check } from "lucide-react";
import apiIllustration from "@/assets/api-illustration.png";
import { useSiteSettings } from "./site-settings-context";

const APISection = () => {
  const { settings, t } = useSiteSettings();

  return (
    <section id="api" className="section-padding bg-card">
      <div className="container-custom">
        <div className="text-center mb-16">
          <h2 className="text-3xl md:text-4xl font-bold text-foreground mb-4">
            {t(settings.apiSection.heading)}
          </h2>
          <p className="text-lg text-muted-foreground max-w-2xl mx-auto">
            {t(settings.apiSection.description)}
          </p>
        </div>

        <div className="grid grid-cols-1 lg:grid-cols-2 gap-12 lg:gap-16 items-center">
          <div className="bg-muted/50 rounded-2xl border border-border p-8">
            <h3 className="text-2xl font-bold text-foreground mb-6">
              {t(settings.apiSection.cardTitle)}
            </h3>

            <ul className="space-y-4">
              {settings.apiSection.features.map((feature, index) => (
                <li key={index} className="flex items-start gap-3">
                  <div className="w-5 h-5 rounded-full bg-secondary/10 flex items-center justify-center shrink-0 mt-0.5">
                    <Check className="w-3 h-3 text-secondary" />
                  </div>
                  <span className="text-foreground">{t(feature)}</span>
                </li>
              ))}
            </ul>
          </div>

          <div className="flex justify-center">
            <img
              src={settings.apiSection.imageUrl || apiIllustration}
              alt="API workflow illustration"
              className="w-full max-w-md object-contain"
              loading="lazy"
            />
          </div>
        </div>
      </div>
    </section>
  );
};

export default APISection;
