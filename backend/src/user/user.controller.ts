import {
  Controller,
  Get,
  Post,
  Body,
  Patch,
  Delete,
  Query,
  Req,
  Res,
  UseGuards,
} from '@nestjs/common';
import { UserService } from './user.service';
import {
  CreateUserDto,
  LoginDto,
  FindOneQueryDto,
  ResetPasswordDto,
  UpdateUserDto,
  UserFilterDto,
  AdminUserDto,
  ChangeRoleDto,
} from './dto/update-user.dto';
import { AuthGuard } from '../lib/auth.guard';
import type { ExpressRequest } from '../lib/auth.guard';
import { RolesGuard } from '../lib/roles.guard';
import { Roles } from '../lib/roles.decorator';
import { UserType } from './entities/user.entity';
import { Throttle, ThrottlerGuard } from '@nestjs/throttler';
import { Response } from 'express';

@Controller('user')
export class UserController {
  constructor(private readonly userService: UserService) {}

  @Post()
  @UseGuards(ThrottlerGuard)
  @Throttle({ default: { limit: 100, ttl: 3600000 } })
  create(@Body() createUserDto: CreateUserDto) {
    return this.userService.create(createUserDto);
  }

  @Post('login')
  @UseGuards(ThrottlerGuard)
  @Throttle({ default: { limit: 600, ttl: 1800000 } })
  async logInUser(
    @Body() loginDto: LoginDto,
    @Res({ passthrough: true }) response: Response,
  ) {
    const loginData = await this.userService.loginUser(loginDto);

    response.cookie('access_token', loginData.access_token, {
      httpOnly: true,
      sameSite: 'lax',
      secure: process.env.NODE_ENV === 'production',
      maxAge: 10 * 24 * 60 * 60 * 1000,
      path: '/',
    });

    return loginData;
  }

  @Get('get-all')
  async findAll(@Query() query: UserFilterDto) {
    return this.userService.findAll(query);
  }

  @Get('get-one')
  findOne(@Query() query: FindOneQueryDto) {
    return this.userService.findOne(query);
  }

  @Get('get-all-admin')
  @UseGuards(AuthGuard, RolesGuard)
  @Roles(UserType.ADMIN)
  getAllUserForAdmin(@Query() query: AdminUserDto) {
    return this.userService.getUserForAdmin(query);
  }

  @Get('get-my-profile')
  @UseGuards(AuthGuard)
  getMyProfile(@Req() req: ExpressRequest) {
    return this.userService.finMyProfile(req.user?.id);
  }

  @Get('get-user-profile-admin')
  @UseGuards(AuthGuard, RolesGuard)
  @Roles(UserType.ADMIN)
  getUserProfile(@Query() query: FindOneQueryDto) {
    return this.userService.findOne(query);
  }

  @Patch('update-profile')
  @UseGuards(AuthGuard, ThrottlerGuard)
  @Throttle({ default: { limit: 500, ttl: 1800000 } })
  update(@Body() updateUserDto: UpdateUserDto, @Req() req: ExpressRequest) {
    return this.userService.update(updateUserDto, req.user?.id);
  }

  @Patch('update-password')
  @UseGuards(AuthGuard, ThrottlerGuard)
  @Throttle({ default: { limit: 60, ttl: 60 } })
  updatePassword(
    @Body() updateUserDto: ResetPasswordDto,
    @Req() req: ExpressRequest,
  ) {
    return this.userService.updatePassword(req.user?.id, updateUserDto);
  }

  @Patch('update-user-admin')
  @UseGuards(AuthGuard, RolesGuard, ThrottlerGuard)
  @Throttle({ default: { limit: 200, ttl: 3600000 } })
  @Roles(UserType.ADMIN)
  UpdateUserAdmin(@Body() updateUserDto: UpdateUserDto) {
    return this.userService.update(updateUserDto);
  }

  @Patch('change-role')
  @UseGuards(AuthGuard, RolesGuard, ThrottlerGuard)
  @Throttle({ default: { limit: 100, ttl: 3600000 } })
  @Roles(UserType.ADMIN)
  changeRole(@Body() changeRoleDto: ChangeRoleDto) {
    return this.userService.changeRole(changeRoleDto);
  }

  @Patch('toggle-subscription')
  @UseGuards(AuthGuard, RolesGuard)
  @Roles(UserType.ADMIN)
  toggleSubscription(@Body() query: FindOneQueryDto) {
    return this.userService.toggleSubscription(query.id);
  }

  @Patch('toggle-active')
  @UseGuards(AuthGuard, RolesGuard)
  @Roles(UserType.ADMIN)
  toggleActive(@Body() query: FindOneQueryDto) {
    return this.userService.toggleUserActive(query.id);
  }

  @Patch('toggle-published')
  @UseGuards(AuthGuard, RolesGuard)
  @Roles(UserType.ADMIN)
  togglePublished(@Body() query: FindOneQueryDto) {
    return this.userService.toggleUserPublished(query.id);
  }

  @Delete('delete-my-account')
  @UseGuards(AuthGuard)
  remove(@Req() req: ExpressRequest) {
    return this.userService.removeUser(req.user?.id);
  }

  @Delete('delete-user-admin')
  @UseGuards(AuthGuard, RolesGuard, ThrottlerGuard)
  @Throttle({ default: { limit: 200, ttl: 3600000 } })
  @Roles(UserType.ADMIN)
  deleteUser(@Query() query: FindOneQueryDto) {
    return this.userService.remove(query);
  }
}
