import { useSiteSettings } from "./site-settings-context";

const TrustedBySection = () => {
  const { settings, t } = useSiteSettings();

  return (
    <section className="section-padding bg-card">
      <div className="container-custom">
        <div className="text-center mb-12">
          <h2 className="text-3xl md:text-4xl font-bold text-foreground mb-4">
            {t(settings.trustedBrands.heading)}
          </h2>
        </div>

        <div className="grid grid-cols-4 sm:grid-cols-6 md:grid-cols-8 gap-4 md:gap-6">
          {settings.trustedBrands.brands.map((brand, index) => (
            <div
              key={index}
              className="h-12 md:h-16 flex items-center justify-center rounded-lg bg-muted/50 border border-border"
            >
              <span className="text-xs md:text-sm font-medium text-muted-foreground/60">
                {brand}
              </span>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
};

export default TrustedBySection;
