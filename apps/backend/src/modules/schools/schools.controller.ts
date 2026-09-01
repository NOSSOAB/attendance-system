import { Controller, Get } from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { SchoolsService } from './schools.service';

@Controller('schools')
export class SchoolsController {
  constructor(private readonly schoolsService: SchoolsService) {}

  @Get()
  @Throttle({
    default: { limit: 1_000, ttl: 60_000 },
    network: { limit: 6_000, ttl: 60_000 },
  })
  async findAll() {
    return this.schoolsService.findAll();
  }
}
