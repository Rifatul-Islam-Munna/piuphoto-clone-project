import { HttpException, Injectable, Logger } from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import axios from 'axios';
import { Model, Types } from 'mongoose';
import { ConfigService } from '@nestjs/config';
import { Addon, AddonDocument } from './entities/addon.entity';
import {
  AddonPurchase,
  AddonPurchaseDocument,
  AddonPurchaseStatus,
} from './entities/addon-purchase.entity';
import {
  AddonFilterDto,
  CreateAddonCheckoutDto,
  CreateAddonDto,
  UpdateAddonDto,
  VerifyAddonCheckoutDto,
} from './dto/create-addon.dto';
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
export class AddonService {
  private logger = new Logger(AddonService.name);

  constructor(
    @InjectModel(Addon.name)
    private addonModel: Model<AddonDocument>,
    @InjectModel(AddonPurchase.name)
    private addonPurchaseModel: Model<AddonPurchaseDocument>,
    @InjectModel(User.name)
    private userModel: Model<UserDocument>,
    private configService: ConfigService,
  ) {}

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

  private toObjectId(id: string) {
    return new Types.ObjectId(id);
  }

  private async createStripeCheckoutSession(
    addon: Record<string, any>,
    userId: string,
  ) {
    const params = new URLSearchParams();
    const frontendBaseUrl = this.getFrontendBaseUrl();

    params.append('mode', 'payment');
    params.append(
      'success_url',
      `${frontendBaseUrl}/#/pricing?addonPurchase=success&addonSessionId={CHECKOUT_SESSION_ID}`,
    );
    params.append(
      'cancel_url',
      `${frontendBaseUrl}/#/pricing?addonPurchase=cancel`,
    );
    params.append('client_reference_id', userId);
    params.append('metadata[userId]', userId);
    params.append('metadata[addonId]', String(addon._id));
    params.append('metadata[credit]', String(addon.credit));
    params.append(
      'line_items[0][price_data][currency]',
      String(addon.currency || 'USD').toLowerCase(),
    );
    params.append('line_items[0][price_data][product_data][name]', addon.title);

    if (addon.description) {
      params.append(
        'line_items[0][price_data][product_data][description]',
        addon.description,
      );
    }

    params.append(
      'line_items[0][price_data][unit_amount]',
      String(Math.round(Number(addon.price) * 100)),
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
      this.logger.error('Stripe checkout session creation failed', error);
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
      this.logger.error('Stripe checkout session verification failed', error);
      throw new HttpException(
        error?.response?.data?.error?.message ||
          'Failed to verify Stripe checkout session',
        400,
      );
    }
  }

  async create(createDto: CreateAddonDto) {
    const created = await this.addonModel.create(createDto);

    if (!created) {
      throw new HttpException('Addon not created', 400);
    }

    return {
      message: 'Addon created successfully',
      data: created,
    };
  }

  async findAll(filter: AddonFilterDto) {
    const { page = 1, limit = 10, query, isActive = 'all' } = filter;
    const skip = (page - 1) * limit;
    const findFilter: Record<string, any> = {};

    if (query?.trim()) {
      findFilter.$or = [
        { title: { $regex: query, $options: 'i' } },
        { description: { $regex: query, $options: 'i' } },
      ];
    }

    if (isActive !== 'all') {
      findFilter.isActive = isActive === 'true';
    }

    const [data, totalItems] = await Promise.all([
      this.addonModel
        .find(findFilter)
        .sort({ order: 1, createdAt: -1 })
        .skip(skip)
        .limit(limit)
        .lean()
        .exec(),
      this.addonModel.countDocuments(findFilter).exec(),
    ]);

    const totalPages = Math.ceil(totalItems / limit);

    return {
      data,
      page,
      limit,
      totalItems,
      totalPages,
      hasNextPage: page < totalPages,
      hasPreviousPage: page > 1,
    };
  }

  async findOne(id: string) {
    const addon = await this.addonModel.findById(id).lean();

    if (!addon) {
      throw new HttpException('Addon not found', 400);
    }

    return addon;
  }

  async update(id: string, updateDto: UpdateAddonDto) {
    const addon = await this.addonModel
      .findByIdAndUpdate(id, { $set: updateDto }, { new: true })
      .lean();

    if (!addon) {
      throw new HttpException('Addon not found', 400);
    }

    return {
      message: 'Addon updated successfully',
      data: addon,
    };
  }

  async remove(id: string) {
    const addon = await this.addonModel.findByIdAndDelete(id).lean();

    if (!addon) {
      throw new HttpException('Addon not found', 400);
    }

    return {
      message: 'Addon deleted successfully',
      data: addon,
    };
  }

  async toggleActive(id: string) {
    const addon = await this.addonModel.findById(id).select('isActive').lean();

    if (!addon) {
      throw new HttpException('Addon not found', 400);
    }

    const updatedAddon = await this.addonModel
      .findByIdAndUpdate(
        id,
        { $set: { isActive: !addon.isActive } },
        { new: true },
      )
      .lean();

    if (!updatedAddon) {
      throw new HttpException('Addon not found', 400);
    }

    return updatedAddon;
  }

  async createCheckoutSession(
    createCheckoutDto: CreateAddonCheckoutDto,
    userId?: string,
  ) {
    if (!userId || !Types.ObjectId.isValid(userId)) {
      throw new HttpException('Invalid user id', 400);
    }

    const { addonId } = createCheckoutDto;

    if (!Types.ObjectId.isValid(addonId)) {
      throw new HttpException('Invalid addon id', 400);
    }

    const addon = await this.addonModel
      .findById(addonId)
      .select('title description credit price currency isActive')
      .lean();

    if (!addon || !addon.isActive) {
      throw new HttpException('Addon not found or inactive', 400);
    }

    const checkoutSession = await this.createStripeCheckoutSession(addon, userId);

    if (!checkoutSession.id || !checkoutSession.url) {
      throw new HttpException('Invalid Stripe checkout session response', 400);
    }

    await this.addonPurchaseModel.findOneAndUpdate(
      { stripeSessionId: checkoutSession.id },
      {
        $set: {
          addonId: this.toObjectId(addonId),
          userId: this.toObjectId(userId),
          credit: addon.credit,
          price: addon.price,
          currency: addon.currency,
          status: AddonPurchaseStatus.PENDING,
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

  async verifyCheckout(verifyDto: VerifyAddonCheckoutDto, userId?: string) {
    if (!userId || !Types.ObjectId.isValid(userId)) {
      throw new HttpException('Invalid user id', 400);
    }

    const { sessionId } = verifyDto;

    const purchase = await this.addonPurchaseModel
      .findOne({ stripeSessionId: sessionId })
      .populate('addonId', 'title credit')
      .lean();

    if (!purchase) {
      throw new HttpException('Purchase not found', 400);
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

    if (stripeSession.metadata?.userId && stripeSession.metadata.userId !== userId) {
      throw new HttpException('Stripe session metadata mismatch', 403);
    }

    if (stripeSession.payment_status !== 'paid') {
      throw new HttpException('Payment not completed yet', 400);
    }

    let creditsAdded = 0;
    let userCredits = 0;

    if (purchase.status === AddonPurchaseStatus.COMPLETED) {
      const existingUser = await this.userModel
        .findById(userId)
        .select('credits')
        .lean();

      userCredits = existingUser?.credits || 0;
    } else {
      const updatedUser = await this.userModel
        .findByIdAndUpdate(
          userId,
          { $inc: { credits: purchase.credit } },
          { new: true },
        )
        .select('credits')
        .lean();

      if (!updatedUser) {
        throw new HttpException('User not found', 400);
      }

      creditsAdded = purchase.credit;
      userCredits = updatedUser.credits || 0;

      await this.addonPurchaseModel.findByIdAndUpdate(purchase._id, {
        $set: {
          status: AddonPurchaseStatus.COMPLETED,
          completedAt: new Date(),
          stripePaymentIntentId: stripeSession.payment_intent || undefined,
        },
      });
    }

    return {
      message: 'Addon purchase verified successfully',
      data: {
        sessionId,
        status: stripeSession.payment_status,
        creditsAdded,
        totalCredits: userCredits,
        addon: purchase.addonId
          ? {
              _id: String((purchase.addonId as any)._id),
              title: (purchase.addonId as any).title,
              credit: (purchase.addonId as any).credit,
            }
          : null,
      },
    };
  }
}

