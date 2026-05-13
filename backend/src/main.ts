import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';
import { ValidationPipe } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { SwaggerModule, DocumentBuilder } from '@nestjs/swagger';
import { AllExceptionsFilter } from './lib/all-exceptions.filter';
import { NestExpressApplication } from '@nestjs/platform-express';
import { existsSync } from 'fs';
import { join } from 'path';

async function bootstrap() {
  const app = await NestFactory.create<NestExpressApplication>(AppModule);

  const configService = app.get(ConfigService);
  const corsOrigin = configService.get<string>('CORS_ORIGIN');

  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      transform: true,
      forbidNonWhitelisted: true,
      transformOptions: {
        enableImplicitConversion: true,
      },
    }),
  );

  app.useGlobalFilters(new AllExceptionsFilter());

 app.enableCors({
  origin: true,
  methods: 'GET,HEAD,PUT,PATCH,POST,DELETE,OPTIONS',
  credentials: true,
});

  const swaggerConfig = new DocumentBuilder()
    .setTitle('PiuPhoto API')
    .setDescription('The PiuPhoto API description')
    .setVersion('1.0')
    .addBearerAuth(
      {
        type: 'http',
        scheme: 'bearer',
        bearerFormat: 'JWT',
        name: 'access_token',
        description: 'Enter JWT token',
        in: 'header',
      },
      'access_token',
    )
    .build();

  const document = SwaggerModule.createDocument(app, swaggerConfig);
  SwaggerModule.setup('api', app, document);

  const frontendDistPath = [
    join(process.cwd(), '../frontend/dist'),
    join(process.cwd(), 'frontend/dist'),
  ].find((path) => existsSync(join(path, 'index.html')));

  if (frontendDistPath) {
    app.useStaticAssets(frontendDistPath, { index: false });
    app.use((req, res, next) => {
      const isPageRequest =
        req.method === 'GET' &&
        req.accepts('html') &&
        !req.path.startsWith('/api') &&
        !req.path.startsWith('/auth') &&
        !req.path.startsWith('/user') &&
        !req.path.startsWith('/album') &&
        !req.path.startsWith('/event') &&
        !req.path.startsWith('/eventImage') &&
        !req.path.startsWith('/image') &&
        !req.path.startsWith('/subscription') &&
        !req.path.startsWith('/subscription-plan') &&
        !req.path.startsWith('/addon') &&
        !req.path.startsWith('/uploads');

      if (!isPageRequest) {
        return next();
      }

      return res.sendFile(join(frontendDistPath, 'index.html'));
    });
  }

  const port = configService.get('PORT') || 3000;
  await app.listen(port);

  console.log(`Application is running on: http://localhost:${port}`);
  console.log(`Swagger docs: http://localhost:${port}/api`);
}

bootstrap();
