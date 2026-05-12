import {
  Injectable,
  CanActivate,
  ExecutionContext,
  UnauthorizedException,
  ForbiddenException,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { UserType } from '../user/entities/user.entity';
import { ExpressRequest } from './auth.guard';
import { ROLES_KEY } from './roles.decorator';

@Injectable()
export class RolesGuard implements CanActivate {
  constructor(private readonly reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    const request: ExpressRequest = context.switchToHttp().getRequest();

    const user = request.user;
    if (!user) {
      throw new UnauthorizedException(
        'You need to be authenticated to access this resource.',
      );
    }

    const requiredRoles: UserType[] = this.reflector.get<UserType[]>(
      ROLES_KEY,
      context.getHandler(),
    );

    if (!requiredRoles) {
      return true;
    }

    const hasRole = requiredRoles.some((role) => user.role?.includes(role));

    if (!hasRole) {
      throw new ForbiddenException(
        'You do not have the necessary permissions.',
      );
    }

    return true;
  }
}