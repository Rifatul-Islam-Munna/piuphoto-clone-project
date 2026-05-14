import { Button } from "@/components/ui/button";
import { Apple, Play } from "lucide-react";
import { useSiteSettings } from "./site-settings-context";

const FinalCTASection = () => {
  const { settings, t } = useSiteSettings();

  return (
    <section className="section-padding gradient-hero relative overflow-hidden">
      <div className="absolute left-0 top-1/2 -translate-y-1/2 w-32 h-64 bg-primary/5 rounded-r-full" />
      <div className="absolute right-0 top-1/2 -translate-y-1/2 w-32 h-64 bg-secondary/5 rounded-l-full" />

      <div className="container-custom relative z-10">
        <div className="text-center max-w-2xl mx-auto">
          <h2 className="text-3xl md:text-4xl lg:text-5xl font-bold text-foreground mb-4">
            {t(settings.finalCta.heading)}
          </h2>
          <p className="text-lg text-muted-foreground mb-10">
            {t(settings.finalCta.description)}
          </p>

          <div className="flex flex-col sm:flex-row items-center justify-center gap-4">
            <Button variant="hero" size="lg" className="w-full sm:w-auto gap-3">
              <Apple className="w-5 h-5" />
              {t(settings.finalCta.appStoreText)}
            </Button>
            <Button variant="hero-outline" size="lg" className="w-full sm:w-auto gap-3">
              <Play className="w-5 h-5" />
              {t(settings.finalCta.playStoreText)}
            </Button>
          </div>
        </div>
      </div>
    </section>
  );
};

export default FinalCTASection;
