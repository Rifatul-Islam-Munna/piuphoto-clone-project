import TestimonialCard from "./TestimonialCard";
import eventPhoto from "@/assets/event-photo.jpg";
import { useSiteSettings } from "./site-settings-context";

const CaseStudySection = () => {
  const { settings, t } = useSiteSettings();

  return (
    <section id="case-studies" className="section-padding gradient-section">
      <div className="container-custom">
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-8 lg:gap-12 items-center">
          <div className="rounded-2xl overflow-hidden border border-border">
            <img
              src={eventPhoto}
              alt="Wedding event photography"
              className="w-full h-auto object-cover"
              loading="lazy"
            />
          </div>

          <TestimonialCard
            quote={t(settings.caseStudy.quote)}
            name={settings.caseStudy.name}
            title={t(settings.caseStudy.title)}
            company={t(settings.caseStudy.company)}
          />
        </div>
      </div>
    </section>
  );
};

export default CaseStudySection;
