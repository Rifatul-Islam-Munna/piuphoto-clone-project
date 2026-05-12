'use client';

import { useMemo, useState } from 'react';
import { Loader2 } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { toast } from 'sonner';
import PricingCard from './PricingCard';
import { Button } from '@/components/ui/button';
import { getFeatureDescription, getLimitDescription } from '@/lib/constants/features';
import { useQueryWrapper } from '../../../api-hooks/react-query-wrapper';

type PlanPermission =
  | { key?: string; value?: number | string }
  | Record<string, unknown>;

type Plan = {
  _id: string;
  title: string;
  description?: string;
  price: number;
  discount_price?: number;
  features: string[];
  permissions?: PlanPermission[];
  isPopular: boolean;
  billingUnit: 'PER_MONTH' | 'PER_YEAR';
  currency?: string;
};

type PlansResponse = {
  data: Plan[];
};

const tabOptions = [
  { label: 'Monthly', value: 'PER_MONTH' as const },
  { label: 'Yearly', value: 'PER_YEAR' as const },
];

const defaultPlans = {
  PER_MONTH: [
    {
      _id: 'silver-month',
      tier: 'silver' as const,
      badge: 'SILVER',
      price: '19.90',
      currency: '$',
      period: '/month',
      features: [
        '50GB PiuCloud storage',
        'Unlimited photographers per album',
        'Brand card and photo watermark',
        'Access URL customization',
        'Unlimited AI Reviewer activations',
      ],
      highlighted: false,
    },
    {
      _id: 'gold-month',
      tier: 'gold' as const,
      badge: 'GOLD',
      price: '79.90',
      currency: '$',
      period: '/month',
      features: [
        '300GB PiuCloud storage',
        'Real-time AI retouch and AI search',
        'Unlimited photographers per album',
        'Video Live support',
        'Album premium features unlocked',
      ],
      highlighted: true,
    },
    {
      _id: 'platinum-month',
      tier: 'platinum' as const,
      badge: 'PLATINUM',
      price: '299.90',
      currency: '$',
      period: '/month',
      features: [
        '1TB PiuCloud storage',
        'Premium branding placements',
        'Video Live and API access',
        'Unlimited AI Reviewer activations',
        'Best fit for events, exhibitions, and sports coverage',
      ],
      highlighted: false,
    },
  ],
  PER_YEAR: [
    {
      _id: 'silver-year',
      tier: 'silver' as const,
      badge: 'SILVER',
      price: '199.00',
      currency: '$',
      period: '/year',
      features: [
        '50GB PiuCloud storage',
        'Unlimited photographers per album',
        'Brand card and photo watermark',
        'Access URL customization',
        'Unlimited AI Reviewer activations',
      ],
      highlighted: false,
    },
    {
      _id: 'gold-year',
      tier: 'gold' as const,
      badge: 'GOLD',
      price: '799.00',
      currency: '$',
      period: '/year',
      features: [
        '300GB PiuCloud storage',
        'Real-time AI retouch and AI search',
        'Unlimited photographers per album',
        'Video Live support',
        'Album premium features unlocked',
      ],
      highlighted: true,
    },
    {
      _id: 'platinum-year',
      tier: 'platinum' as const,
      badge: 'PLATINUM',
      price: '2999.00',
      currency: '$',
      period: '/year',
      features: [
        '1TB PiuCloud storage',
        'Premium branding placements',
        'Video Live and API access',
        'Unlimited AI Reviewer activations',
        'Best fit for events, exhibitions, and sports coverage',
      ],
      highlighted: false,
    },
  ],
};

const getTierFromTitle = (title: string) => {
  const normalized = title.toLowerCase();

  if (normalized.includes('platinum')) return 'platinum' as const;
  if (normalized.includes('gold')) return 'gold' as const;
  return 'silver' as const;
};

const normalizePermissions = (permissions: PlanPermission[] = []) => {
  const normalized: string[] = [];

  permissions.forEach((permission) => {
    if (permission?.key && permission.value !== undefined && permission.value !== null) {
      normalized.push(`${getLimitDescription(String(permission.key))}: ${permission.value}`);
      return;
    }

    Object.entries(permission || {}).forEach(([key, value]) => {
      if (key === '_id' || key === 'id' || value === undefined || value === null) {
        return;
      }

      normalized.push(`${getLimitDescription(key)}: ${value}`);
    });
  });

  return normalized;
};

const PricingSection = () => {
  const navigate = useNavigate();
  const [billingUnit, setBillingUnit] = useState<'PER_MONTH' | 'PER_YEAR'>('PER_MONTH');

  const { data: plansData, isLoading } = useQueryWrapper<PlansResponse>(
    ['home-plans'],
    '/subscription-plan/get-all?limit=100&isActive=true',
    { withCredentials: true },
  );

  const groupedPlans = useMemo(() => {
    const apiPlans = plansData?.data || [];

    if (apiPlans.length === 0) {
      return defaultPlans;
    }

    const next = {
      PER_MONTH: [] as Array<Record<string, unknown>>,
      PER_YEAR: [] as Array<Record<string, unknown>>,
    };

    apiPlans.forEach((plan) => {
      const mappedPlan = {
        _id: plan._id,
        tier: getTierFromTitle(plan.title),
        badge: plan.title?.toUpperCase() || 'PLAN',
        price: String(plan.discount_price ?? plan.price ?? 0),
        originalPrice:
          plan.discount_price !== undefined &&
          plan.discount_price !== null &&
          Number(plan.discount_price) !== Number(plan.price)
            ? String(plan.price ?? 0)
            : undefined,
        currency: plan.currency === 'USD' ? '$' : `${plan.currency || '$'} `,
        period: plan.billingUnit === 'PER_YEAR' ? '/year' : '/month',
        features: [
          ...((plan.features || []).map((feature) => getFeatureDescription(feature))),
          ...normalizePermissions(plan.permissions || []),
        ],
        highlighted: plan.isPopular,
      };

      next[plan.billingUnit || 'PER_MONTH'].push(mappedPlan);
    });

    return {
      PER_MONTH: next.PER_MONTH.length ? next.PER_MONTH : defaultPlans.PER_MONTH,
      PER_YEAR: next.PER_YEAR.length ? next.PER_YEAR : defaultPlans.PER_YEAR,
    };
  }, [plansData]);

  const visiblePlans = groupedPlans[billingUnit];

  const handleBuyNow = (planName: string) => {
    const token = localStorage.getItem('access_token');

    if (!token) {
      toast.error('Please login to continue');
      navigate('/login');
      return;
    }

    toast.info(`Plan selected: ${planName}`);
  };

  return (
    <section id="pricing" className="section-padding bg-card">
      <div className="container-custom">
        <div className="mb-16 text-center">
          <h2 className="mb-4 text-3xl font-bold text-foreground md:text-4xl">
            Plans & Billing
          </h2>
          <p className="mx-auto max-w-2xl text-lg text-muted-foreground">
            Real subscription plans, readable features, monthly and yearly view
          </p>
        </div>

        <div className="mb-10 flex justify-center">
          <div className="inline-flex rounded-full border border-border bg-muted p-1">
            {tabOptions.map((tab) => (
              <Button
                key={tab.value}
                type="button"
                variant={billingUnit === tab.value ? 'default' : 'ghost'}
                className="rounded-full px-6"
                onClick={() => setBillingUnit(tab.value)}
              >
                {tab.label}
              </Button>
            ))}
          </div>
        </div>

        {isLoading ? (
          <div className="flex h-32 items-center justify-center">
            <Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
          </div>
        ) : (
          <div className="mx-auto grid max-w-6xl grid-cols-1 gap-8 md:grid-cols-3">
            {visiblePlans.map((plan: any) => (
              <PricingCard
                key={plan._id}
                tier={plan.tier}
                badge={plan.badge}
                price={plan.price}
                originalPrice={plan.originalPrice as string | undefined}
                currency={plan.currency}
                period={plan.period}
                features={plan.features}
                highlighted={plan.highlighted}
                buttonText="Buy Now"
                onBuyNow={() => handleBuyNow(plan.badge)}
              />
            ))}
          </div>
        )}
      </div>
    </section>
  );
};

export default PricingSection;
