import { Test, TestingModule } from '@nestjs/testing';
import { PrismaTenantService } from '../../database/prisma/prisma-tenant.service';
import { PrismaService } from '../../database/prisma/prisma.service';
import { AuthService } from './auth.service';
import { JwtService } from '@nestjs/jwt';

describe('AuthService', () => {
  let service: AuthService;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        AuthService,
        {
          provide: JwtService,
          useValue: { signAsync: jest.fn() },
        },
        {
          provide: PrismaService,
          useValue: {
            school: {
              findUnique: jest.fn(),
            },
          },
        },
        {
          provide: PrismaTenantService,
          useValue: {
            getClient: jest.fn(),
          },
        },
      ],
    }).compile();

    service = module.get<AuthService>(AuthService);
  });

  it('should be defined', () => {
    expect(service).toBeDefined();
  });
});
