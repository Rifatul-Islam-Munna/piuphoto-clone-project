import { Check } from "lucide-react";
import apiIllustration from "@/assets/api-illustration.png";

const apiFeatures = [
  "Simple REST API with comprehensive documentation",
  "Real-time webhooks for instant updates",
  "SDKs for all major platforms",
  "99.9% uptime SLA guarantee",
];

const APISection = () => {
  return (
    <section id="api" className="section-padding bg-card">
      <div className="container-custom">
        <div className="text-center mb-16">
          <h2 className="text-3xl md:text-4xl font-bold text-foreground mb-4">
            API Integration for Every Company
          </h2>
          <p className="text-lg text-muted-foreground max-w-2xl mx-auto">
            Seamlessly integrate nikofly into your existing workflow
          </p>
        </div>

        <div className="grid grid-cols-1 lg:grid-cols-2 gap-12 lg:gap-16 items-center">
          {/* Content */}
          <div className="bg-muted/50 rounded-2xl border border-border p-8">
            <h3 className="text-2xl font-bold text-foreground mb-6">
              Integrate nikofly in your product or website with ease
            </h3>

            <ul className="space-y-4">
              {apiFeatures.map((feature, index) => (
                <li key={index} className="flex items-start gap-3">
                  <div className="w-5 h-5 rounded-full bg-secondary/10 flex items-center justify-center shrink-0 mt-0.5">
                    <Check className="w-3 h-3 text-secondary" />
                  </div>
                  <span className="text-foreground">{feature}</span>
                </li>
              ))}
            </ul>
          </div>

          {/* Illustration */}
          <div className="flex justify-center">
            <img
              src={apiIllustration}
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
