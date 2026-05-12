import TestimonialCard from "./TestimonialCard";
import eventPhoto from "@/assets/event-photo.jpg";

const CaseStudySection = () => {
  return (
    <section id="case-studies" className="section-padding gradient-section">
      <div className="container-custom">
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-8 lg:gap-12 items-center">
          {/* Event Photo */}
          <div className="rounded-2xl overflow-hidden border border-border">
            <img
              src={eventPhoto}
              alt="Wedding event photography"
              className="w-full h-auto object-cover"
              loading="lazy"
            />
          </div>

          {/* Testimonial */}
          <TestimonialCard
            quote="nikofly transformed how we deliver wedding photos. Guests can now see and share their photos in real-time, creating an unforgettable experience. Our client satisfaction has never been higher."
            name="Sarah Chen"
            title="Lead Photographer"
            company="Eternal Moments Photography"
          />
        </div>
      </div>
    </section>
  );
};

export default CaseStudySection;
