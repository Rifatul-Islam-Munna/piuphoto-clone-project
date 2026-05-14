import { Button } from "@/components/ui/button";
import { Link } from "react-router-dom";
import { Check } from "lucide-react";
import phoneMockup from "@/assets/phone-mockup.png";
import { useSiteSettings } from "./site-settings-context";

const EventStreamingSection = () => {
  const { settings, t } = useSiteSettings();

  return (
    <section id="ai-magic" className="section-padding gradient-section">
      <div className="container-custom">
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-12 lg:gap-16 items-center">
          <div className="flex justify-center order-2 lg:order-1">
            <img
              src={phoneMockup}
              alt="Event photo gallery on phone"
              className="w-56 md:w-64 lg:w-72 object-contain"
              loading="lazy"
            />
          </div>

          <div className="order-1 lg:order-2">
            <h2 className="text-3xl md:text-4xl font-bold text-foreground mb-6">
              {t(settings.eventStreaming.heading)}
            </h2>

            <div className="flex flex-wrap gap-3 mb-8">
              {settings.eventStreaming.chips.map((chip, index) => (
                <Button
                  key={`${chip.en}-${index}`}
                  variant="outline"
                  size="sm"
                  className={index === 0 ? "border-primary text-primary" : "border-secondary text-secondary"}
                >
                  {t(chip)}
                </Button>
              ))}
              <Button variant="default" size="sm" asChild>
                <Link to="/login">{t(settings.eventStreaming.ctaLabel)}</Link>
              </Button>
            </div>

            <ul className="space-y-4">
              {settings.eventStreaming.features.map((feature, index) => (
                <li key={index} className="flex items-start gap-3">
                  <div className="w-5 h-5 rounded-full bg-primary/10 flex items-center justify-center shrink-0 mt-0.5">
                    <Check className="w-3 h-3 text-primary" />
                  </div>
                  <span className="text-foreground">{t(feature)}</span>
                </li>
              ))}
            </ul>
          </div>
        </div>
      </div>
    </section>
  );
};

export default EventStreamingSection;
