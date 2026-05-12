import camera from "@/assets/camera.png";
import phoneMockup from "@/assets/phone-mockup.png";
import { Instagram, Facebook, Twitter, MessageCircle } from "lucide-react";

const socialIcons = [
  { icon: Instagram, label: "Instagram" },
  { icon: Facebook, label: "Facebook" },
  { icon: Twitter, label: "Twitter" },
  { icon: MessageCircle, label: "WhatsApp" },
];

const FlyPhotosSection = () => {
  return (
    <section className="section-padding gradient-cream">
      <div className="container-custom">
        <div className="text-center mb-16">
          <h2 className="text-3xl md:text-4xl font-bold text-foreground mb-4">
            Fly Your Photos Everywhere
          </h2>
          <p className="text-lg text-muted-foreground max-w-2xl mx-auto">
            From camera to phone to social media - share your moments instantly
          </p>
        </div>

        <div className="grid grid-cols-1 lg:grid-cols-3 gap-8 lg:gap-12 items-center">
          {/* Camera */}
          <div className="flex justify-center">
            <img
              src={camera}
              alt="Professional DSLR Camera"
              className="w-full max-w-xs lg:max-w-sm object-contain animate-float"
              loading="lazy"
            />
          </div>

          {/* Phone Mockup */}
          <div className="flex justify-center order-first lg:order-none">
            <img
              src={phoneMockup}
              alt="Phone showing photo gallery"
              className="w-48 md:w-56 lg:w-64 object-contain"
              loading="lazy"
            />
          </div>

          {/* Social Icons Stack */}
          <div className="flex justify-center">
            <div className="flex flex-row lg:flex-col gap-4">
              {socialIcons.map(({ icon: Icon, label }, index) => (
                <div
                  key={label}
                  className="w-12 h-12 rounded-xl bg-card border border-border flex items-center justify-center card-hover"
                  style={{ animationDelay: `${index * 0.1}s` }}
                >
                  <Icon className="w-6 h-6 text-muted-foreground" />
                </div>
              ))}
              <div className="hidden lg:flex flex-col gap-4">
                <div className="w-12 h-12 rounded-xl bg-card border border-border flex items-center justify-center card-hover">
                  <span className="text-lg">📷</span>
                </div>
                <div className="w-12 h-12 rounded-xl bg-card border border-border flex items-center justify-center card-hover">
                  <span className="text-lg">💬</span>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
};

export default FlyPhotosSection;
