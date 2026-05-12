import {
  Injectable,
  CanActivate,
  ExecutionContext,
  UnauthorizedException,
  Logger,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { Request } from 'express';

export type JwtPayload = {
  email: string;
  id: string;
  role: string;
  phone: string;
};

export interface ExpressRequest extends Request {
  user: JwtPayload;
}

@Injectable()
export class AuthGuard implements CanActivate {
  private logger = new Logger(AuthGuard.name);

  constructor(
    private readonly jwtService: JwtService,
    private readonly configService: ConfigService,
  ) {}

  canActivate(context: ExecutionContext): boolean | Promise<boolean> {
    const request: ExpressRequest = context.switchToHttp().getRequest();

    const token = this.getTokenFromRequest(request);
    this.logger.log('access_token----->', token);

    if (!token) {
      throw new UnauthorizedException('No token found');
    }

    return this.validateToken(request, token);
  }

  private getTokenFromRequest(request: ExpressRequest): string | null {
    const headerToken = request.headers['access_token'] as string | undefined;
    if (headerToken) {
      return headerToken;
    }

    const authHeader = request.headers.authorization;
    if (authHeader?.startsWith('Bearer ')) {
      return authHeader.slice(7);
    }

    const cookieHeader = request.headers.cookie;
    if (!cookieHeader) {
      return null;
    }

    const cookies = cookieHeader.split(';').map((cookie) => cookie.trim());
    const accessTokenCookie = cookies.find((cookie) =>
      cookie.startsWith('access_token='),
    );

    return accessTokenCookie?.slice('access_token='.length) ?? null;
  }

  private async validateToken(
    request: ExpressRequest,
    token: string,
  ): Promise<boolean> {
    try {
      const secret = this.configService.get<string>('ACCESS_TOKEN');
      this.logger.log('🔑 SECRET in Auth:', secret);

      const decoded = await this.jwtService.verifyAsync<JwtPayload>(token, {
        secret: secret,
      });

      if (!decoded) {
        throw new Error('Token verification returned no payload');
      }

      this.logger.log('decoded->', decoded);

      if (!decoded.id || !decoded.role) {
        throw new Error('Incomplete JWT payload');
      }

      request.user = decoded;

      return true;
    } catch (error) {
      this.logger.debug('token-error->', error);
      throw new UnauthorizedException('Invalid or expired token');
    }
  }
}
