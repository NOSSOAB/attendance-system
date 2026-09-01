import { Global, Module } from '@nestjs/common';
import { PrismaTenantService } from './prisma-tenant.service';
import { PrismaService } from './prisma.service';

@Global()
@Module({
  providers: [PrismaService, PrismaTenantService],
  exports: [PrismaService, PrismaTenantService],
})
export class PrismaModule {}
