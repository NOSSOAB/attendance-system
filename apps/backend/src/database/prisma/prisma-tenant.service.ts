import 'dotenv/config';
import { Injectable, OnModuleDestroy } from '@nestjs/common';
import { PrismaPg } from '@prisma/adapter-pg';
import { PrismaClient } from '@prisma/client';
import { createPgPoolConfig } from './pg-pool.config';

export type TenantAuthRole = 'student' | 'lecturer';

@Injectable()
export class PrismaTenantService implements OnModuleDestroy {
  private readonly clients = new Map<string, PrismaClient>();

  getClient(schoolCode: string, role: TenantAuthRole) {
    const connectionString = this.resolveConnectionString(schoolCode, role);
    const existingClient = this.clients.get(connectionString);

    if (existingClient) {
      return existingClient;
    }

    const adapter = new PrismaPg(createPgPoolConfig(connectionString));
    const client = new PrismaClient({ adapter });

    this.clients.set(connectionString, client);
    return client;
  }

  async onModuleDestroy() {
    await Promise.all(
      [...this.clients.values()].map(async (client) => client.$disconnect()),
    );
  }

  private resolveConnectionString(schoolCode: string, role: TenantAuthRole) {
    const normalizedSchoolCode = schoolCode.trim().toUpperCase();
    const normalizedRole = role.trim().toUpperCase();
    const envKey = `${normalizedSchoolCode}_${normalizedRole}_DATABASE_URL`;
    const value = process.env[envKey];

    if (value && value.trim().length > 0) {
      return value.trim();
    }

    throw new Error(
      `Không tìm thấy cấu hình cơ sở dữ liệu riêng cho trường ${normalizedSchoolCode} và vai trò ${normalizedRole}. Cần khai báo biến ${envKey}.`,
    );
  }
}
