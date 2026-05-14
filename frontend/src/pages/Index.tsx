import { useEffect } from "react";
import Navbar from "@/components/landing/Navbar";
import HeroSection from "@/components/landing/HeroSection";
import ProductShowcase from "@/components/landing/ProductShowcase";
import FeaturesGrid from "@/components/landing/FeaturesGrid";
import FlyPhotosSection from "@/components/landing/FlyPhotosSection";
import EventStreamingSection from "@/components/landing/EventStreamingSection";
import APISection from "@/components/landing/APISection";
import ConnectionSection from "@/components/landing/ConnectionSection";
import PricingSection from "@/components/landing/PricingSection";
import TrustedBySection from "@/components/landing/TrustedBySection";
import CaseStudySection from "@/components/landing/CaseStudySection";
import NewsroomSection from "@/components/landing/NewsroomSection";
import FinalCTASection from "@/components/landing/FinalCTASection";
import Footer from "@/components/landing/Footer";
import { useSearchParams } from "react-router-dom";

const Index = () => {
  const [searchParams, setSearchParams] = useSearchParams();

  useEffect(() => {
    const section = searchParams.get("section");
    if (!section) return;

    const element = document.getElementById(section);
    if (!element) return;

    const timer = window.setTimeout(() => {
      element.scrollIntoView({ behavior: "smooth", block: "start" });
      const nextParams = new URLSearchParams(searchParams);
      nextParams.delete("section");
      setSearchParams(nextParams, { replace: true });
    }, 80);

    return () => window.clearTimeout(timer);
  }, [searchParams, setSearchParams]);

  return (
    <div className="min-h-screen">
      <Navbar />
      <main>
        <HeroSection />
        <ProductShowcase />
        <FeaturesGrid />
        <FlyPhotosSection />
        <EventStreamingSection />
        <APISection />
        <ConnectionSection />
        <PricingSection />
        <TrustedBySection />
        <CaseStudySection />
        <NewsroomSection />
        <FinalCTASection />
      </main>
      <Footer />
    </div>
  );
};

export default Index;
