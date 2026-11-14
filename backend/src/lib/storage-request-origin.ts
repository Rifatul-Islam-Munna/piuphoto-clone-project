import type { Request } from 'express';

export function storageRequestOrigin(request: Request): string {
  const forwardedProtocol = request.get('x-forwarded-proto')?.split(',')[0].trim();
  const protocol = ['http', 'https'].includes(forwardedProtocol)
    ? forwardedProtocol
    : request.protocol;
  return `${protocol}://${request.get('host')}`;
}
