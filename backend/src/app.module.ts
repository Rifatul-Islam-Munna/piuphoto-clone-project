import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { MongooseModule } from '@nestjs/mongoose';
import { Connection } from 'mongoose';
import { JwtModule } from '@nestjs/jwt';
import { ThrottlerModule } from '@nestjs/throttler';
import virtuals from 'mongoose-lean-virtuals';
import { UserModule } from './user/user.module';
import { SubscriptionModule } from './subscription/subscription.module';
import { ImageModule } from './image/image.module';
import { EventModule } from './event/event.module';

@Module({
  imports: [
    ThrottlerModule.forRoot([
      {
        ttl: 60000,
        limit: 1000,
        getTracker: (req) => {
          const getHeader = (headerName: string): string | null => {
            const value = req.headers[headerName];
            if (!value) return null;

            const str = typeof value === 'string' ? value : value[0];
            return str?.trim() || null;
          };

          const ip =
            getHeader('cf-connecting-ip') ||
            getHeader('x-forwarded-for')?.split(',')[0]?.trim() ||
            getHeader('x-real-ip') ||
            getHeader('true-client-ip') ||
            getHeader('x-client-ip') ||
            req.ip ||
            'unknown';

          return ip;
        },
      },
    ]),
    ConfigModule.forRoot({
      isGlobal: true,
    }),
    JwtModule.register({
      global: true,
      secret: process.env.ACCESS_TOKEN,
      signOptions: { expiresIn: '1d' },
    }),
    MongooseModule.forRoot(process.env.MONGODB_URL as string, {
      autoIndex: true,
      onConnectionCreate: (connection: Connection) => {
        connection.on('connected', () => console.log('connected'));
        connection.on('open', () => console.log('open'));
        connection.on('disconnected', () => console.log('disconnected'));
        connection.on('reconnected', () => console.log('reconnected'));
        connection.on('disconnecting', () => console.log('disconnecting'));

        return connection;
      },
      connectionFactory: (connection: Connection) => {
        connection.plugin(virtuals);
        return connection;
      },
    }),
    UserModule,
    SubscriptionModule,
    ImageModule,
    EventModule,
  ],
  controllers: [],
  providers: [],
})
export class AppModule {}