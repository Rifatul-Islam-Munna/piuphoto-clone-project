import PricingCard from "./PricingCard";

const pricingPlans = [
  {
    tier: "silver" as const,
    badge: "SILVER",
    price: "19.90",
    period: "/month",
    features: [
      "50GB PiuCloud storage",
      "Unlimited photographers per album",
      "Brand card and photo watermark",
      "Access URL customization",
      "Unlimited AI Reviewer activations",
    ],
  },
  {
    tier: "gold" as const,
    badge: "GOLD",
    price: "79.90",
    period: "/month",
    features: [
      "300GB PiuCloud storage",
      "Real-time AI retouch and AI search",
      "Unlimited photographers per album",
      "Video Live support",
      "Album premium features unlocked",
      "Brand card, watermark, and URL customization",
    ],
    highlighted: true,
  },
  {
    tier: "platinum" as const,
    badge: "PLATINUM",
    price: "299.90",
    period: "/month",
    features: [
      "1TB PiuCloud storage",
      "Premium branding placements",
      "Video Live and API access",
      "Unlimited AI Reviewer activations",
      "Brand card, watermark, and URL customization",
      "Best fit for events, exhibitions, and sports coverage",
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
            Membership-style plans inspired by Piufoto event workflows
          </p>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-3 gap-8 max-w-5xl mx-auto">
          {pricingPlans.map((plan, index) => (
            <PricingCard
              key={index}
              tier={plan.tier}
              badge={plan.badge}
              price={plan.price}
              period={plan.period}
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
