import {
  HttpException,
  Injectable,
  Logger,
  OnModuleInit,
} from '@nestjs/common';
import { CreateUserDto } from './dto/create-user.dto';
import {
  AdminUserDto,
  FindOneQueryDto,
  LoginDto,
  ResetPasswordDto,
  UpdateUserDto,
  UserFilterDto,
  ChangeRoleDto,
} from './dto/update-user.dto';
import { InjectModel } from '@nestjs/mongoose';
import { User, UserDocument } from './entities/user.entity';
import { Model, Types } from 'mongoose';
import bcrypt from 'bcrypt';
import { JwtService } from '@nestjs/jwt';
import { ConfigService } from '@nestjs/config';
import { v4 as uuidv4 } from 'uuid';

@Injectable()
export class UserService implements OnModuleInit {
  private logger = new Logger(UserService.name);

  constructor(
    @InjectModel(User.name)
    private userModel: Model<UserDocument>,
    private jwtService: JwtService,
    private configService: ConfigService,
  ) {}

  async onModuleInit() {
    await this.ensurePhoneNumberIndex();
    await this.ensureEmailIndex();
    await this.createDefaultAdmin();
  }

  private async createDefaultAdmin() {
    const adminEmail = this.configService.get<string>('ADMIN_EMAIL');
    const adminPassword = this.configService.get<string>('ADMIN_PASSWORD');

    if (!adminEmail || !adminPassword) {
      this.logger.warn('Admin credentials not configured');
      return;
    }

    const adminExists = await this.userModel
      .findOne({ email: adminEmail, role: 'admin' as any })
      .lean()
      .exec();

    if (!adminExists) {
      const passwordHash = await bcrypt.hash(adminPassword, 10);
      await this.userModel.create({
        name: 'Admin',
        email: adminEmail,
        password: passwordHash,
        role: 'admin' as any,
        isActive: true,
        isPublished: true,
        isEmailVerified: true,
      });
      this.logger.log('Default admin created');
    }
  }

  private async ensurePhoneNumberIndex() {
    const currentIndexes = await this.userModel.collection.indexes();
    const hasExpectedPhoneIndex = currentIndexes.some(
      (index) =>
        index.name === 'phone_1' &&
        index.unique === true &&
        index.partialFilterExpression?.phone?.$type === 'string',
    );

    if (hasExpectedPhoneIndex) {
      return;
    }

    const legacyPhoneIndex = currentIndexes.find(
      (index) => index.name === 'phone_1',
    );

    if (legacyPhoneIndex) {
      this.logger.warn('Replacing legacy phone_1 index');
      await this.userModel.collection.dropIndex('phone_1');
    }

    await this.userModel.collection.createIndex(
      { phone: 1 },
      {
        name: 'phone_1',
        unique: true,
        partialFilterExpression: {
          phone: { $type: 'string' },
        },
      },
    );
  }

  private async ensureEmailIndex() {
    const currentIndexes = await this.userModel.collection.indexes();
    const hasExpectedEmailIndex = currentIndexes.some(
      (index) =>
        index.name === 'email_1' &&
        index.unique === true &&
        index.partialFilterExpression?.email?.$type === 'string',
    );

    if (hasExpectedEmailIndex) {
      return;
    }

    const legacyEmailIndex = currentIndexes.find(
      (index) => index.name === 'email_1',
    );

    if (legacyEmailIndex) {
      this.logger.warn('Replacing legacy email_1 index');
      await this.userModel.collection.dropIndex('email_1');
    }

    await this.userModel.collection.createIndex(
      { email: 1 },
      {
        name: 'email_1',
        unique: true,
        partialFilterExpression: {
          email: { $type: 'string' },
        },
      },
    );
  }

  async create(createUserDto: CreateUserDto) {
    if (!createUserDto.email || !createUserDto.password) {
      throw new HttpException('Email and password are required', 400);
    }

    const findExistingUser = await this.userModel
      .findOne({ email: createUserDto.email })
      .lean()
      .exec();

    if (findExistingUser) {
      throw new HttpException('User already exists', 400);
    }

    const passwordHash = await bcrypt.hash(createUserDto.password, 10);

    const userIdCount = uuidv4().slice(0, 6);
    const finalData = {
      ...createUserDto,
      password: passwordHash,
      userId: userIdCount,
    };

    const create = await this.userModel.create(finalData);

    if (!create) {
      throw new HttpException('User not created', 400);
    }

    return { message: 'User created successfully', data: create };
  }

  async verifyOtp(otp: string) {
    throw new HttpException('OTP verification not available', 400);
  }

  async loginUser(loginUserDto: LoginDto) {
    const { email, password } = loginUserDto;

    if (!email || !password) {
      throw new HttpException('Email and password are required', 400);
    }

    const findOneUser = await this.userModel
      .findOne({ email })
      .select('email id role phone name password userId gender')
      .lean();

    if (!findOneUser) {
      throw new HttpException('User not found', 400);
    }

    const isMatch = await bcrypt.compare(password, findOneUser.password);

    if (!isMatch) {
      throw new HttpException('Invalid credentials', 400);
    }

    const secret = this.configService.get<string>('ACCESS_TOKEN');
    const access_token = await this.jwtService.sign(
      {
        email: findOneUser.email ?? '',
        id: findOneUser._id,
        role: findOneUser.role,
        phone: findOneUser.phone ?? '',
      },
      { expiresIn: '10d', secret: secret },
    );

    return {
      message: 'User logged in successfully',
      access_token,
      user: findOneUser,
    };
  }

  async findAll(userQuery: UserFilterDto) {
    const {
      query,
      page = 1,
      limit = 10,
      gender,
      role,
      ageMin,
      ageMax,
      isActive,
    } = userQuery;

    const skip = (page - 1) * limit;
    const filter: any = {};

    if (query) {
      filter.$text = { $search: query };
    }

    if (gender && gender !== 'all') {
      filter.gender = gender;
    }

    if (role && role.length > 0 && !role.includes('all')) {
      filter.role = { $in: role };
    }

    if (ageMin !== undefined || ageMax !== undefined) {
      filter.age = {};
      if (ageMin !== undefined) filter.age.$gte = ageMin;
      if (ageMax !== undefined) filter.age.$lte = ageMax;
    }

    if (isActive !== undefined && isActive !== 'all') {
      filter.isActive = isActive === 'true';
    }

    const [data, totalItems] = await Promise.all([
      this.userModel
        .find(filter)
        .select('name email phone userId role gender age maritalStatus isActive isPublished createdAt')
        .skip(skip)
        .limit(limit)
        .sort({ createdAt: -1 })
        .lean()
        .exec(),
      this.userModel.countDocuments(filter).exec(),
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

  async findOne(query: FindOneQueryDto) {
    const { id } = query;

    const isValidObjectId = Types.ObjectId.isValid(id);

    let findOne;

    if (isValidObjectId) {
      findOne = await this.userModel
        .findById(id)
        .select('-password')
        .lean();
    }

    if (!findOne) {
      findOne = await this.userModel
        .findOne({ userId: id })
        .select('-password')
        .lean();
    }

    if (!findOne) {
      findOne = await this.userModel
        .findOne({ phone: id })
        .select('-password')
        .lean();
    }

    if (!findOne) {
      throw new HttpException('User not found', 400);
    }

    return findOne;
  }

  async finMyProfile(id: string) {
    const findOne = await this.userModel
      .findById(id)
      .select('-password')
      .lean();

    if (!findOne) {
      throw new HttpException('User not found', 400);
    }

    return findOne;
  }

  async update(updateUserDto: UpdateUserDto, userId?: string) {
    const { id, password, otpNumber, otpValidatedAt, _v, updatedAt, createdAt, ...rest } = updateUserDto as any;

    const targetId = userId || id;

    if (!targetId) {
      throw new HttpException('User ID is required', 400);
    }

    const findOne = await this.userModel
      .findByIdAndUpdate(targetId, { $set: rest }, { new: true })
      .lean();

    if (!findOne) {
      throw new HttpException('User not found', 400);
    }

    return { message: 'User updated successfully', data: findOne };
  }

  async updatePassword(id: string, updateDto: ResetPasswordDto) {
    const { oldPassword, newPassword } = updateDto;

    const findOne = await this.userModel
      .findById(id)
      .select('password')
      .lean();

    if (!findOne) {
      throw new HttpException('User not found', 400);
    }

    const isMatch = await bcrypt.compare(oldPassword, findOne.password);

    if (!isMatch) {
      throw new HttpException('Invalid credentials', 400);
    }

    const passwordHash = await bcrypt.hash(newPassword, 10);

    const updatePassword = await this.userModel
      .findByIdAndUpdate(id, { $set: { password: passwordHash } }, { new: true })
      .lean();

    if (!updatePassword) {
      throw new HttpException('User not found', 400);
    }

    return { message: 'Password updated successfully' };
  }

  async removeUser(id: string) {
    const findOne = await this.userModel.findByIdAndDelete(id).lean();

    if (!findOne) {
      throw new HttpException('User not found', 400);
    }

    return { message: 'User deleted successfully', data: findOne };
  }

  async remove(query: FindOneQueryDto) {
    const { id } = query;
    const findOne = await this.userModel.findByIdAndDelete(id).lean();

    if (!findOne) {
      throw new HttpException('User not found', 400);
    }

    return { message: 'User deleted successfully', data: findOne };
  }

  async getUserForAdmin(query: AdminUserDto) {
    const {
      page = 1,
      limit = 10,
      gender = 'all',
      query: searchQuery,
      isPublished,
      isActive,
    } = query;

    const skip = (page - 1) * limit;
    const filter: any = {};

    if (searchQuery && searchQuery.trim()) {
      filter.$text = { $search: searchQuery };
    }

    if (gender && gender !== 'all') {
      filter.gender = gender;
    }

    if (isPublished !== undefined && isPublished !== null && isPublished !== 'all') {
      filter.isPublished = isPublished === 'true';
    }

    if (isActive !== undefined && isActive !== null && isActive !== 'all') {
      filter.isActive = isActive === 'true';
    }

    const [data, totalItems] = await Promise.all([
      this.userModel
        .find(filter)
        .select('name email phone whatsapp maritalStatus isActive isPublished userId')
        .skip(skip)
        .limit(limit)
        .sort({ createdAt: -1 })
        .lean()
        .exec(),
      this.userModel.countDocuments(filter).exec(),
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

  async toggleSubscription(userId: string) {
    throw new HttpException('Subscription feature not available', 400);
  }

  async changeRole(changeRoleDto: ChangeRoleDto) {
    const { userId, role } = changeRoleDto;

    const updateRole = await this.userModel
      .findByIdAndUpdate(userId, { $set: { role } }, { new: true })
      .lean();

    if (!updateRole) {
      throw new HttpException('User not found', 400);
    }

    return { message: 'Role updated successfully', data: updateRole };
  }

  async toggleUserActive(userId: string) {
    const findOne = await this.userModel
      .findById(userId)
      .select('isActive')
      .lean();

    if (!findOne) {
      throw new HttpException('User not found', 400);
    }

    const updateActive = await this.userModel
      .findByIdAndUpdate(
        userId,
        { $set: { isActive: !findOne.isActive } },
        { new: true },
      )
      .lean();

    if (!updateActive) {
      throw new HttpException('User not found', 400);
    }

    return updateActive;
  }

  async toggleUserPublished(userId: string) {
    const findOne = await this.userModel
      .findById(userId)
      .select('isPublished')
      .lean();

    if (!findOne) {
      throw new HttpException('User not found', 400);
    }

    const updatePublished = await this.userModel
      .findByIdAndUpdate(
        userId,
        { $set: { isPublished: !findOne.isPublished } },
        { new: true },
      )
      .lean();

    if (!updatePublished) {
      throw new HttpException('User not found', 400);
    }

    return updatePublished;
  }
}