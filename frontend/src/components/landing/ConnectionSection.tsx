import { Button } from "@/components/ui/button";
import { Link } from "react-router-dom";
import { Cable, Wifi } from "lucide-react";
import connectionDiagram from "@/assets/connection-diagram.png";
import { useSiteSettings } from "./site-settings-context";

const ConnectionSection = () => {
  const { settings, t } = useSiteSettings();

  return (
    <section id="connect" className="section-padding gradient-hero">
      <div className="container-custom">
        <div className="text-center mb-16">
          <h2 className="text-3xl md:text-4xl font-bold text-foreground mb-4">
            {t(settings.connectionSection.heading)}
          </h2>
          <p className="text-lg text-muted-foreground max-w-2xl mx-auto">
            {t(settings.connectionSection.description)}
          </p>
        </div>

        <div className="grid grid-cols-1 lg:grid-cols-3 gap-8 items-center mb-12">
          <div className="bg-card rounded-xl border border-border p-6 card-hover">
            <div className="w-12 h-12 rounded-xl bg-primary/10 flex items-center justify-center mb-4">
              <Cable className="w-6 h-6 text-primary" />
            </div>
            <h3 className="text-xl font-bold text-foreground mb-2">
              {t(settings.connectionSection.wiredTitle)}
            </h3>
            <p className="text-muted-foreground">
              {t(settings.connectionSection.wiredDescription)}
            </p>
          </div>

          <div className="flex justify-center">
            <img
              src={settings.connectionSection.imageUrl || connectionDiagram}
              alt="Camera to phone connection"
              className="w-full max-w-sm object-contain"
              loading="lazy"
            />
          </div>

          <div className="bg-card rounded-xl border border-border p-6 card-hover">
            <div className="w-12 h-12 rounded-xl bg-secondary/10 flex items-center justify-center mb-4">
              <Wifi className="w-6 h-6 text-secondary" />
            </div>
            <h3 className="text-xl font-bold text-foreground mb-2">
              {t(settings.connectionSection.wirelessTitle)}
            </h3>
            <p className="text-muted-foreground">
              {t(settings.connectionSection.wirelessDescription)}
            </p>
          </div>
        </div>

        <div className="text-center">
          <Button variant="default" size="lg" asChild>
            <Link to="/login">{t(settings.connectionSection.ctaLabel)}</Link>
          </Button>
        </div>
      </div>
    </section>
  );
};

export default ConnectionSection;
