import { HttpException, Injectable, Logger } from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import axios from 'axios';
import { ConfigService } from '@nestjs/config';
import { Model } from 'mongoose';
import {
  SubscriptionPlan,
  SubscriptionPlanDocument,
  BillingUnit,
} from './entities/subscription-plan.entity';
import {
  SubscriptionPlanPurchase,
  SubscriptionPlanPurchaseDocument,
  SubscriptionPlanPurchaseStatus,
} from './entities/subscription-plan-purchase.entity';
import { Addon, AddonDocument } from '../addon/entities/addon.entity';
import {
  AddonPurchase,
  AddonPurchaseDocument,
} from '../addon/entities/addon-purchase.entity';
import {
  CreateSubscriptionPlanDto,
  UpdateSubscriptionPlanDto,
  SubscriptionPlanFilterDto,
  FindOnePlanDto,
} from './dto/create-subscription-plan.dto';
import { UserService } from '../user/user.service';
import { User, UserDocument } from '../user/entities/user.entity';

type StripeCheckoutSession = {
  id: string;
  url?: string;
  payment_status?: string;
  payment_intent?: string | null;
  client_reference_id?: string | null;
  metadata?: Record<string, string | undefined>;
};

@Injectable()
export class SubscriptionPlanService {
  private logger = new Logger(SubscriptionPlanService.name);

  constructor(
    @InjectModel(SubscriptionPlan.name)
    private subscriptionPlanModel: Model<SubscriptionPlanDocument>,
    @InjectModel(SubscriptionPlanPurchase.name)
    private subscriptionPlanPurchaseModel: Model<SubscriptionPlanPurchaseDocument>,
    @InjectModel(Addon.name)
    private addonModel: Model<AddonDocument>,
    @InjectModel(AddonPurchase.name)
    private addonPurchaseModel: Model<AddonPurchaseDocument>,
    @InjectModel(User.name)
    private userModel: Model<UserDocument>,
    private userService: UserService,
    private configService: ConfigService,
  ) {}

  private stripLegacyPlanFields<T extends Record<string, any> | null>(plan: T): T {
    if (!plan) {
      return plan;
    }

    delete plan.credit;
    delete plan.monthlyCreateLimit;

    return plan;
  }

  private normalizePermissions(
    permissions?: Record<string, unknown>[],
  ): { key: string; value: number }[] {
    if (!Array.isArray(permissions)) {
      return [];
    }

    return permissions.flatMap((permission) => {
      if (
        permission?.key &&
        permission.value !== undefined &&
        permission.value !== null
      ) {
        const numericValue = Number(permission.value);

        if (!Number.isNaN(numericValue)) {
          return [{ key: String(permission.key), value: numericValue }];
        }
      }

      return Object.entries(permission)
        .filter(([key]) => key !== '_id' && key !== 'id')
        .map(([key, value]) => ({
          key,
          value: Number(value),
        }))
        .filter((entry) => !Number.isNaN(entry.value));
    });
  }

  private extractPermissionLimit(
    permissions: Record<string, unknown>[] = [],
    key: string,
  ) {
    for (const permission of permissions) {
      if (
        permission?.key === key &&
        permission.value !== undefined &&
        permission.value !== null
      ) {
        const numericValue = Number(permission.value);

        if (!Number.isNaN(numericValue)) {
          return numericValue;
        }
      }

      if (
        Object.prototype.hasOwnProperty.call(permission, key) &&
        permission[key] !== undefined &&
        permission[key] !== null
      ) {
        const numericValue = Number(permission[key]);

        if (!Number.isNaN(numericValue)) {
          return numericValue;
        }
      }
    }

    return 0;
  }

  private getStripeSecretKey() {
    const stripeSecretKey =
      this.configService.get<string>('STRIPE_SECRET_KEY')?.trim() || '';

    if (!stripeSecretKey) {
      throw new HttpException('Stripe secret key missing', 500);
    }

    return stripeSecretKey;
  }

  private getFrontendBaseUrl() {
    const configuredOrigins =
      this.configService.get<string>('CORS_ORIGIN')?.trim() || '';

    if (!configuredOrigins) {
      return 'http://localhost:8080';
    }

    return configuredOrigins.split(',')[0].trim();
  }

  private async createStripeCheckoutSession(
    plan: Record<string, any>,
    userId: string,
    credit: number,
  ) {
    const params = new URLSearchParams();
    const frontendBaseUrl = this.getFrontendBaseUrl();

    params.append('mode', 'payment');
    params.append(
      'success_url',
      `${frontendBaseUrl}/#/pricing?planPurchase=success&planSessionId={CHECKOUT_SESSION_ID}`,
    );
    params.append(
      'cancel_url',
      `${frontendBaseUrl}/#/pricing?planPurchase=cancel`,
    );
    params.append('client_reference_id', userId);
    params.append('metadata[userId]', userId);
    params.append('metadata[planId]', String(plan._id));
    params.append('metadata[credit]', String(credit));
    params.append(
      'line_items[0][price_data][currency]',
      String(plan.currency || 'USD').toLowerCase(),
    );
    params.append('line_items[0][price_data][product_data][name]', plan.title);

    if (plan.description) {
      params.append(
        'line_items[0][price_data][product_data][description]',
        plan.description,
      );
    }

    params.append(
      'line_items[0][price_data][unit_amount]',
      String(Math.round(Number(plan.discount_price ?? plan.price) * 100)),
    );
    params.append('line_items[0][quantity]', '1');

    try {
      const { data } = await axios.post<StripeCheckoutSession>(
        'https://api.stripe.com/v1/checkout/sessions',
        params.toString(),
        {
          headers: {
            Authorization: `Bearer ${this.getStripeSecretKey()}`,
            'Content-Type': 'application/x-www-form-urlencoded',
          },
        },
      );

      return data;
    } catch (error: any) {
      this.logger.error('Stripe plan checkout session creation failed', error);
      throw new HttpException(
        error?.response?.data?.error?.message ||
          'Failed to create Stripe checkout session',
        400,
      );
    }
  }

  private async getStripeCheckoutSession(sessionId: string) {
    try {
      const { data } = await axios.get<StripeCheckoutSession>(
        `https://api.stripe.com/v1/checkout/sessions/${sessionId}`,
        {
          headers: {
            Authorization: `Bearer ${this.getStripeSecretKey()}`,
          },
        },
      );

      return data;
    } catch (error: any) {
      this.logger.error('Stripe plan checkout verification failed', error);
      throw new HttpException(
        error?.response?.data?.error?.message ||
          'Failed to verify Stripe checkout session',
        400,
      );
    }
  }

  async create(createDto: CreateSubscriptionPlanDto) {
    const create = await this.subscriptionPlanModel.create({
      ...createDto,
      permissions: this.normalizePermissions(createDto.permissions),
    });

    if (!create) {
      throw new HttpException('Plan not created', 400);
    }

    return {
      message: 'Plan created successfully',
      data: this.stripLegacyPlanFields(create.toObject()),
    };
  }

  async findAll(filter: SubscriptionPlanFilterDto) {
    const { page = 1, limit = 10, billingUnit, isActive, isPopular, query } =
      filter;

    const skip = (page - 1) * limit;
    const findFilter: any = {};

    if (billingUnit) {
      findFilter.billingUnit = billingUnit;
    }

    if (isActive !== undefined && isActive !== 'all') {
      findFilter.isActive = isActive === 'true';
    }

    if (isPopular !== undefined && isPopular !== 'all') {
      findFilter.isPopular = isPopular === 'true';
    }

    if (query) {
      findFilter.title = { $regex: query, $options: 'i' };
    }

    const [data, totalItems] = await Promise.all([
      this.subscriptionPlanModel
        .find(findFilter)
        .sort({ order: 1 })
        .skip(skip)
        .limit(limit)
        .lean()
        .exec(),
      this.subscriptionPlanModel.countDocuments(findFilter).exec(),
    ]);

    const totalPages = Math.ceil(totalItems / limit);

    return {
      data: data.map((plan) => this.stripLegacyPlanFields(plan)),
      page,
      limit,
      totalItems,
      totalPages,
      hasNextPage: page < totalPages,
      hasPreviousPage: page > 1,
    };
  }

  async findOne(findOneDto: FindOnePlanDto) {
    const { id } = findOneDto;

    const findOne = await this.subscriptionPlanModel.findById(id).lean();

    if (!findOne) {
      throw new HttpException('Plan not found', 400);
    }

    return this.stripLegacyPlanFields(findOne);
  }

  async update(updateDto: UpdateSubscriptionPlanDto, id: string) {
    const { permissions, ...rest } = updateDto;

    const findOne = await this.subscriptionPlanModel
      .findByIdAndUpdate(
        id,
        {
          $set: {
            ...rest,
            ...(permissions ? { permissions: this.normalizePermissions(permissions) } : {}),
          },
          $unset: { credit: '', monthlyCreateLimit: '' },
        },
        { new: true },
      )
      .lean();

    if (!findOne) {
      throw new HttpException('Plan not found', 400);
    }

    return {
      message: 'Plan updated successfully',
      data: this.stripLegacyPlanFields(findOne),
    };
  }

  async remove(id: string) {
    const findOne = await this.subscriptionPlanModel
      .findByIdAndDelete(id)
      .lean();

    if (!findOne) {
      throw new HttpException('Plan not found', 400);
    }

    return {
      message: 'Plan deleted successfully',
      data: this.stripLegacyPlanFields(findOne),
    };
  }

  async toggleActive(id: string) {
    const findOne = await this.subscriptionPlanModel
      .findById(id)
      .select('isActive')
      .lean();

    if (!findOne) {
      throw new HttpException('Plan not found', 400);
    }

    const updateActive = await this.subscriptionPlanModel
      .findByIdAndUpdate(
        id,
        { $set: { isActive: !findOne.isActive } },
        { new: true },
      )
      .lean();

    if (!updateActive) {
      throw new HttpException('Plan not found', 400);
    }

    return this.stripLegacyPlanFields(updateActive);
  }

  async togglePopular(id: string) {
    const findOne = await this.subscriptionPlanModel
      .findById(id)
      .select('isPopular')
      .lean();

    if (!findOne) {
      throw new HttpException('Plan not found', 400);
    }

    const updatePopular = await this.subscriptionPlanModel
      .findByIdAndUpdate(
        id,
        { $set: { isPopular: !findOne.isPopular } },
        { new: true },
      )
      .lean();

    if (!updatePopular) {
      throw new HttpException('Plan not found', 400);
    }

    return this.stripLegacyPlanFields(updatePopular);
  }

  async createCheckoutSession(planId: string, userId?: string) {
    if (!userId) {
      throw new HttpException('Invalid user id', 400);
    }

    const plan = await this.subscriptionPlanModel
      .findById(planId)
      .select(
        'title description price discount_price currency billingUnit permissions isActive',
      )
      .lean();

    if (!plan || !plan.isActive) {
      throw new HttpException('Plan not found or inactive', 400);
    }

    const credit = this.extractPermissionLimit(
      Array.isArray(plan.permissions) ? plan.permissions : [],
      'credit',
    );

    const checkoutSession = await this.createStripeCheckoutSession(
      plan,
      userId,
      credit,
    );

    if (!checkoutSession.id || !checkoutSession.url) {
      throw new HttpException('Invalid Stripe checkout session response', 400);
    }

    await this.subscriptionPlanPurchaseModel.findOneAndUpdate(
      { stripeSessionId: checkoutSession.id },
      {
        $set: {
          planId: (plan as any)._id,
          userId,
          price: Number(plan.discount_price ?? plan.price),
          currency: plan.currency || 'USD',
          billingUnit: plan.billingUnit || BillingUnit.PER_MONTH,
          credit,
          status: SubscriptionPlanPurchaseStatus.PENDING,
        },
      },
      {
        upsert: true,
        new: true,
        setDefaultsOnInsert: true,
      },
    );

    return {
      message: 'Checkout session created successfully',
      data: {
        sessionId: checkoutSession.id,
        url: checkoutSession.url,
      },
    };
  }

  async verifyCheckout(sessionId: string, userId?: string) {
    if (!userId) {
      throw new HttpException('Invalid user id', 400);
    }

    const purchase = await this.subscriptionPlanPurchaseModel
      .findOne({ stripeSessionId: sessionId })
      .lean();

    if (!purchase) {
      throw new HttpException('Plan purchase not found', 400);
    }

    if (String(purchase.userId) !== userId) {
      throw new HttpException('You can only verify your own purchase', 403);
    }

    const stripeSession = await this.getStripeCheckoutSession(sessionId);

    if (
      stripeSession.client_reference_id &&
      stripeSession.client_reference_id !== userId
    ) {
      throw new HttpException('Stripe session does not belong to this user', 403);
    }

    if (stripeSession.payment_status !== 'paid') {
      throw new HttpException('Payment not completed yet', 400);
    }

    let creditsAdded = 0;
    let totalCredits = 0;
    const plan = purchase.planId
      ? await this.subscriptionPlanModel
          .findById(purchase.planId)
          .select('title')
          .lean()
      : null;

    if (purchase.status === SubscriptionPlanPurchaseStatus.COMPLETED) {
      const profile = await this.userService.finMyProfile(userId);
      totalCredits = profile?.credits || 0;
    } else {
      const normalizedPlanId =
        purchase.planId &&
        typeof (purchase.planId as any)?.toHexString === 'function'
          ? (purchase.planId as any).toHexString()
          : String(purchase.planId);

      const assignedPlan = await this.userService.assignPlan(
        userId,
        normalizedPlanId,
        { creditOverride: purchase.credit },
      );

      creditsAdded = purchase.credit;
      totalCredits = assignedPlan?.data?.credits || 0;

      await this.subscriptionPlanPurchaseModel.findByIdAndUpdate(purchase._id, {
        $set: {
          status: SubscriptionPlanPurchaseStatus.COMPLETED,
          completedAt: new Date(),
          stripePaymentIntentId: stripeSession.payment_intent || undefined,
        },
      });
    }

    return {
      message: 'Plan purchase verified successfully',
      data: {
        sessionId,
        creditsAdded,
        totalCredits,
        plan: plan
          ? {
              _id: String(plan._id),
              title: plan.title,
            }
          : null,
      },
    };
  }

  async getPurchaseHistory(type = 'all') {
    const [planPurchases, addonPurchases] = await Promise.all([
      this.subscriptionPlanPurchaseModel
        .find(type === 'addon' ? { _id: null as any } : {})
        .populate('planId', 'title')
        .populate('userId', 'name email phone userId')
        .sort({ createdAt: -1 })
        .lean()
        .exec(),
      this.addonPurchaseModel
        .find(type === 'plan' ? { _id: null as any } : {})
        .populate('addonId', 'title')
        .populate('userId', 'name email phone userId')
        .sort({ createdAt: -1 })
        .lean()
        .exec(),
    ]);

    const normalizedPlanPurchases = planPurchases.map((purchase: any) => ({
      _id: String(purchase._id),
      type: 'plan',
      status: purchase.status,
      stripeSessionId: purchase.stripeSessionId,
      stripePaymentIntentId: purchase.stripePaymentIntentId || null,
      price: purchase.price,
      currency: purchase.currency,
      credit: purchase.credit,
      createdAt: purchase.createdAt,
      completedAt: purchase.completedAt || null,
      item: purchase.planId
        ? {
            _id: String(purchase.planId._id),
            title: purchase.planId.title,
          }
        : null,
      user: purchase.userId
        ? {
            _id: String(purchase.userId._id),
            name: purchase.userId.name,
            email: purchase.userId.email || null,
            phone: purchase.userId.phone || null,
            userId: purchase.userId.userId || null,
          }
        : null,
    }));

    const normalizedAddonPurchases = addonPurchases.map((purchase: any) => {
      return {
        _id: String(purchase._id),
        type: 'addon',
        status: purchase.status,
        stripeSessionId: purchase.stripeSessionId,
        stripePaymentIntentId: purchase.stripePaymentIntentId || null,
        price: purchase.price,
        currency: purchase.currency,
        credit: purchase.credit,
        createdAt: purchase.createdAt,
        completedAt: purchase.completedAt || null,
        item: purchase.addonId
          ? {
              _id: String(purchase.addonId._id),
              title: purchase.addonId.title,
            }
          : null,
        user: purchase.userId
          ? {
              _id: String(purchase.userId._id),
              name: purchase.userId.name,
              email: purchase.userId.email || null,
              phone: purchase.userId.phone || null,
              userId: purchase.userId.userId || null,
            }
          : null,
      };
    });

    const data = [...normalizedPlanPurchases, ...normalizedAddonPurchases].sort(
      (a, b) =>
        new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime(),
    );

    return {
      data,
      totalItems: data.length,
    };
  }

  async getInvoiceDetails(id: string, type: 'plan' | 'addon') {
    if (type === 'plan') {
      const purchase = await this.subscriptionPlanPurchaseModel
        .findById(id)
        .populate('planId', 'title description')
        .populate('userId', 'name email phone userId')
        .lean();

      if (!purchase) {
        throw new HttpException('Invoice not found', 400);
      }

      return {
        type: 'plan',
        invoiceNumber: `PLAN-${String(purchase._id).slice(-8).toUpperCase()}`,
        status: purchase.status,
        stripeSessionId: purchase.stripeSessionId,
        stripePaymentIntentId: purchase.stripePaymentIntentId || null,
        createdAt: purchase.createdAt,
        completedAt: purchase.completedAt || null,
        price: purchase.price,
        currency: purchase.currency,
        credit: purchase.credit,
        item: purchase.planId,
        user: purchase.userId,
      };
    }

    const purchase = await this.addonPurchaseModel
      .findById(id)
      .populate('addonId', 'title description')
      .populate('userId', 'name email phone userId')
      .lean();

    if (!purchase) {
      throw new HttpException('Invoice not found', 400);
    }

    return {
      type: 'addon',
      invoiceNumber: `ADD-${String(purchase._id).slice(-8).toUpperCase()}`,
      status: purchase.status,
      stripeSessionId: purchase.stripeSessionId,
      stripePaymentIntentId: purchase.stripePaymentIntentId || null,
      createdAt: purchase.createdAt,
      completedAt: purchase.completedAt || null,
      price: purchase.price,
      currency: purchase.currency,
      credit: purchase.credit,
      item: purchase.addonId,
      user: purchase.userId,
    };
  }
}
