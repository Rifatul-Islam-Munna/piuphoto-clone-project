import { Button } from "@/components/ui/button";
import { Link } from "react-router-dom";
import { Check } from "lucide-react";
import phoneMockup from "@/assets/phone-mockup.png";

const features = [
  "AI-powered photo selection and curation",
  "Automatic enhancement and beautification",
  "Real-time streaming to all guests",
  "Instant social media sharing",
  "Cloud backup for all photos",
];

const EventStreamingSection = () => {
  return (
    <section id="ai-magic" className="section-padding gradient-section">
      <div className="container-custom">
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-12 lg:gap-16 items-center">
          {/* Phone Mockup */}
          <div className="flex justify-center order-2 lg:order-1">
            <img
              src={phoneMockup}
              alt="Event photo gallery on phone"
              className="w-56 md:w-64 lg:w-72 object-contain"
              loading="lazy"
            />
          </div>

          {/* Content */}
          <div className="order-1 lg:order-2">
            <h2 className="text-3xl md:text-4xl font-bold text-foreground mb-6">
              Instant Event Streaming and Photo Organization
            </h2>

            <div className="flex flex-wrap gap-3 mb-8">
              <Button variant="outline" size="sm" className="border-primary text-primary">
                AI Selection
              </Button>
              <Button variant="outline" size="sm" className="border-secondary text-secondary">
                AI Beautify
              </Button>
              <Button variant="default" size="sm" asChild>
                <Link to="/login">Get Started</Link>
              </Button>
            </div>

            <ul className="space-y-4">
              {features.map((feature, index) => (
                <li key={index} className="flex items-start gap-3">
                  <div className="w-5 h-5 rounded-full bg-primary/10 flex items-center justify-center shrink-0 mt-0.5">
                    <Check className="w-3 h-3 text-primary" />
                  </div>
                  <span className="text-foreground">{feature}</span>
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
