import FeatureCard from "./FeatureCard";
import { useSiteSettings } from "./site-settings-context";

const FeaturesGrid = () => {
  const { settings, t } = useSiteSettings();

  return (
    <section id="features" className="section-padding bg-card">
      <div className="container-custom">
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-6">
          {settings.featuresGrid.items.map((feature, index) => (
            <FeatureCard
              key={index}
              icon={feature.icon}
              title={t(feature.title)}
              description={t(feature.description)}
              variant={feature.variant}
            />
          ))}
        </div>
      </div>
    </section>
  );
};

export default FeaturesGrid;
