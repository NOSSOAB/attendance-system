import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { App } from 'supertest/types';
import { AppModule } from './../src/app.module';
import { JwtService } from '@nestjs/jwt';

describe('Health (e2e)', () => {
  let app: INestApplication<App>;

  beforeEach(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = moduleFixture.createNestApplication();
    await app.init();
  });

  afterEach(async () => {
    await app.close();
  });

  it('/health (GET)', () => {
    return request(app.getHttpServer())
      .get('/health')
      .expect(200)
      .expect({ status: 'ok' });
  });

  it('rejects a protected endpoint without a token', () => {
    return request(app.getHttpServer()).get('/students/home').expect(401);
  });

  it('rejects a lecturer token on a student endpoint', async () => {
    const jwt = app.get(JwtService);
    const accessToken = await jwt.signAsync({
      sub: 1,
      role: 'lecturer',
      schoolCode: 'HUCE',
      code: 'GV001',
    });

    return request(app.getHttpServer())
      .get('/students/home')
      .set('Authorization', `Bearer ${accessToken}`)
      .expect(403);
  });
});
