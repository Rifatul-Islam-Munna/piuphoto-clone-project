import { Instagram, Twitter, Linkedin, Youtube, Facebook } from "lucide-react";
import { useSiteSettings } from "./site-settings-context";

const socialLinks = [
  { icon: Instagram, href: "#", label: "Instagram" },
  { icon: Twitter, href: "#", label: "Twitter" },
  { icon: Facebook, href: "#", label: "Facebook" },
  { icon: Linkedin, href: "#", label: "LinkedIn" },
  { icon: Youtube, href: "#", label: "YouTube" },
];

const Footer = () => {
  const { settings, t } = useSiteSettings();
  const brandLetter = settings.site.title?.trim()?.charAt(0)?.toLowerCase() || "n";

  return (
    <footer className="bg-dark-section text-white py-16 px-6">
      <div className="container-custom">
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-12 mb-12">
          <div>
            <a href="#" className="flex items-center gap-2 mb-4">
              {settings.site.logoUrl ? (
                <img
                  src={settings.site.logoUrl}
                  alt={settings.site.title}
                  className="h-8 w-8 rounded-lg object-cover"
                />
              ) : (
                <div className="w-8 h-8 rounded-lg bg-gradient-to-br from-primary to-secondary flex items-center justify-center">
                  <span className="text-white font-bold text-lg">{brandLetter}</span>
                </div>
              )}
              <span className="font-bold text-xl">{settings.site.title}</span>
            </a>
            <p className="text-white/60 text-sm leading-relaxed mb-6">
              {t(settings.footer.description)}
            </p>
            <div className="flex gap-3">
              {socialLinks.map(({ icon: Icon, href, label }) => (
                <a
                  key={label}
                  href={href}
                  className="w-10 h-10 rounded-lg border border-white/10 flex items-center justify-center text-white/60 hover:text-white hover:border-white/30 transition-colors"
                  aria-label={label}
                >
                  <Icon className="w-5 h-5" />
                </a>
              ))}
            </div>
          </div>

          <div>
            <h4 className="font-semibold text-white mb-4">{t(settings.footer.featuresHeading)}</h4>
            <ul className="space-y-3">
              {settings.footer.featuresLinks.map((link) => (
                <li key={`${link.href}-${link.label.en}`}>
                  <a href={link.href} className="text-white/60 text-sm hover:text-white transition-colors">
                    {t(link.label)}
                  </a>
                </li>
              ))}
            </ul>
          </div>

          <div>
            <h4 className="font-semibold text-white mb-4">{t(settings.footer.companyHeading)}</h4>
            <ul className="space-y-3">
              {settings.footer.companyLinks.map((link) => (
                <li key={`${link.href}-${link.label.en}`}>
                  <a href={link.href} className="text-white/60 text-sm hover:text-white transition-colors">
                    {t(link.label)}
                  </a>
                </li>
              ))}
            </ul>
          </div>

          <div>
            <h4 className="font-semibold text-white mb-4">{t(settings.footer.contactHeading)}</h4>
            <ul className="space-y-3">
              {settings.footer.contactLinks.map((link) => (
                <li key={`${link.href}-${link.label.en}`}>
                  <a href={link.href} className="text-white/60 text-sm hover:text-white transition-colors">
                    {t(link.label)}
                  </a>
                </li>
              ))}
            </ul>
          </div>
        </div>

        <div className="border-t border-white/10 pt-8 flex flex-col md:flex-row items-center justify-between gap-4">
          <p className="text-white/40 text-sm">
            {t(settings.footer.copyrightText)}
          </p>
          <div className="flex gap-6">
            {settings.footer.legalLinks.map((link) => (
              <a
                key={`${link.href}-${link.label.en}`}
                href={link.href}
                className="text-white/40 text-sm hover:text-white transition-colors"
              >
                {t(link.label)}
              </a>
            ))}
          </div>
        </div>
      </div>
    </footer>
  );
};

export default Footer;
