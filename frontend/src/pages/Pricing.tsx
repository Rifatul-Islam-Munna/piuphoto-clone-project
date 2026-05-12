import Navbar from "@/components/landing/Navbar";
import Footer from "@/components/landing/Footer";
import PricingSection from "@/components/landing/PricingSection";

export default function Pricing() {
  return (
    <div className="min-h-screen flex flex-col">
      <Navbar />
      <main className="flex-1 pt-20">
        <PricingSection />
      </main>
      <Footer />
    </div>
  );
}
