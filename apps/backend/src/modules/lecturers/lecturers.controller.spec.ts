import { Test, TestingModule } from '@nestjs/testing';
import { LecturersController } from './lecturers.controller';
import { LecturersService } from './lecturers.service';
import { JwtService } from '@nestjs/jwt';

describe('LecturersController', () => {
  let controller: LecturersController;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      controllers: [LecturersController],
      providers: [
        {
          provide: JwtService,
          useValue: { verifyAsync: jest.fn() },
        },
        {
          provide: LecturersService,
          useValue: {},
        },
      ],
    }).compile();

    controller = module.get<LecturersController>(LecturersController);
  });

  it('should be defined', () => {
    expect(controller).toBeDefined();
  });
});
