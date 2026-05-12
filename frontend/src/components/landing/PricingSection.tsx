import PricingCard from "./PricingCard";

const pricingPlans = [
  {
    tier: "silver" as const,
    badge: "BASIC",
    price: "0.30",
    features: [
      "Up to 500 photos per event",
      "Basic AI selection",
      "Email support",
      "Standard transfer speed",
      "7-day cloud storage",
    ],
  },
  {
    tier: "gold" as const,
    badge: "PRO",
    price: "0.26",
    features: [
      "Up to 2,000 photos per event",
      "Advanced AI selection & beautify",
      "Priority support",
      "Fast transfer speed",
      "30-day cloud storage",
      "Custom branding",
    ],
    highlighted: true,
  },
  {
    tier: "platinum" as const,
    badge: "PREMIUM",
    price: "0.23",
    features: [
      "Unlimited photos per event",
      "Full AI suite",
      "24/7 dedicated support",
      "Ultra-fast transfer speed",
      "Unlimited cloud storage",
      "White-label solution",
      "API access",
    ],
  },
];

const PricingSection = () => {
  return (
    <section id="pricing" className="section-padding bg-card">
      <div className="container-custom">
        <div className="text-center mb-16">
          <h2 className="text-3xl md:text-4xl font-bold text-foreground mb-4">
            Plans & Billing
          </h2>
          <p className="text-lg text-muted-foreground max-w-2xl mx-auto">
            Choose the perfect plan for your photography needs
          </p>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-3 gap-8 max-w-5xl mx-auto">
          {pricingPlans.map((plan, index) => (
            <PricingCard
              key={index}
              tier={plan.tier}
              badge={plan.badge}
              price={plan.price}
              features={plan.features}
              highlighted={plan.highlighted}
            />
          ))}
        </div>
      </div>
    </section>
  );
};

export default PricingSection;
