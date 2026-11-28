import { ValidationPipe } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { NestExpressApplication } from '@nestjs/platform-express';
import helmet from 'helmet';
import { AppModule } from './app.module';
import { config } from './config';

export function configureApp(app: NestExpressApplication) {
  // Photos are sent once as base64 JPEG (up to 6 MB, about 8 MB encoded).
  app.useBodyParser('json', { limit: '10mb' });
  app.set('trust proxy', 1);
  app.disable('x-powered-by');
  app.setGlobalPrefix('api');
  app.use(helmet({ contentSecurityPolicy: false }));
  app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true, forbidNonWhitelisted: false }));
  return app;
}

async function bootstrap() {
  config.jwtSecret; // fail fast without a secret
  const app = configureApp(await NestFactory.create<NestExpressApplication>(AppModule));
  await app.listen(Number(process.env.PORT ?? 3020), process.env.HOST ?? '0.0.0.0');
}

if (require.main === module) {
  void bootstrap();
}
