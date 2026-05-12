import { HttpException, Injectable, Logger } from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { Model } from 'mongoose';
import {
  SubscriptionPlan,
  SubscriptionPlanDocument,
} from './entities/subscription-plan.entity';
import {
  CreateSubscriptionPlanDto,
  UpdateSubscriptionPlanDto,
  SubscriptionPlanFilterDto,
  FindOnePlanDto,
} from './dto/create-subscription-plan.dto';

@Injectable()
export class SubscriptionPlanService {
  private logger = new Logger(SubscriptionPlanService.name);

  constructor(
    @InjectModel(SubscriptionPlan.name)
    private subscriptionPlanModel: Model<SubscriptionPlanDocument>,
  ) {}

  private stripLegacyPlanFields<T extends Record<string, any> | null>(plan: T): T {
    if (!plan) {
      return plan;
    }

    delete plan.credit;
    delete plan.monthlyCreateLimit;

    return plan;
  }

  async create(createDto: CreateSubscriptionPlanDto) {
    const create = await this.subscriptionPlanModel.create(createDto);

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
    const { ...rest } = updateDto;

    const findOne = await this.subscriptionPlanModel
      .findByIdAndUpdate(
        id,
        {
          $set: rest,
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
}
