import {
  IsIn,
  IsNotEmpty,
  IsObject,
  IsOptional,
  IsString,
} from 'class-validator';

export class FalWebhookQueryDto {
  @IsString()
  @IsNotEmpty()
  type: string;
}

export class FalWebhookDto {
  @IsString()
  @IsNotEmpty()
  request_id: string;

  @IsString()
  @IsOptional()
  gateway_request_id?: string;

  @IsIn(['OK', 'ERROR'])
  status: 'OK' | 'ERROR';

  @IsObject()
  @IsOptional()
  payload?: {
    images?: Array<{ url?: string }>;
    [key: string]: unknown;
  } | null;

  @IsString()
  @IsOptional()
  error?: string;

  @IsString()
  @IsOptional()
  payload_error?: string;
}
