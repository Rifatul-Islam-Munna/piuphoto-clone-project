import FeatureCard from "./FeatureCard";

const features = [
  {
    icon: "📱",
    title: "Real-Time Photo Transfer",
    description: "Photos fly from camera to phone instantly",
    variant: "yellow" as const,
  },
  {
    icon: "⚡",
    title: "Lightning Fast",
    description: "Upload speeds optimized for events",
    variant: "blue" as const,
  },
  {
    icon: "🎯",
    title: "Event-Based Sorting",
    description: "Organize photos by event automatically",
    variant: "purple" as const,
  },
  {
    icon: "🔒",
    title: "Secure & Private",
    description: "Enterprise-grade security for your photos",
    variant: "pink" as const,
  },
];

const FeaturesGrid = () => {
  return (
    <section id="features" className="section-padding bg-card">
      <div className="container-custom">
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-6">
          {features.map((feature, index) => (
            <FeatureCard
              key={index}
              icon={feature.icon}
              title={feature.title}
              description={feature.description}
              variant={feature.variant}
            />
          ))}
        </div>
      </div>
    </section>
  );
};

export default FeaturesGrid;
