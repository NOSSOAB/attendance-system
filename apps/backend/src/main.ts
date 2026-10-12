import { ValidationPipe } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import type { Express } from 'express';
import helmet from 'helmet';
import { AppModule } from './app.module';
import { parseRegistry } from './modules/attendance/ble-c6-verifier';

async function bootstrap() {
  if (
    process.env.NODE_ENV === 'production' &&
    process.env.ATTENDANCE_REQUIRE_BLE !== 'false'
  ) {
    const devices = parseRegistry(process.env.BLE_C6_DEVICES_JSON ?? '');
    if (devices.size === 0) {
      throw new Error(
        'Production BLE attendance requires registered ESP32-C6 devices',
      );
    }
  }
  const app = await NestFactory.create(AppModule);
  app.use(helmet());
  const expressApp = app.getHttpAdapter().getInstance() as Express;
  expressApp.set('trust proxy', 1);
  app.useGlobalPipes(
    new ValidationPipe({
      transform: true,
      whitelist: true,
      forbidNonWhitelisted: true,
    }),
  );

  const configuredOrigins = process.env.CORS_ORIGIN?.split(',')
    .map((origin) => origin.trim())
    .filter(Boolean);
  const isProduction = process.env.NODE_ENV === 'production';
  app.enableCors({
    origin:
      configuredOrigins?.length && !configuredOrigins.includes('*')
        ? configuredOrigins
        : !isProduction,
    methods: ['GET', 'POST', 'PATCH', 'OPTIONS'],
    allowedHeaders: ['Authorization', 'Content-Type'],
  });

  await app.listen(Number(process.env.PORT ?? 3000), '0.0.0.0');
}
void bootstrap();
