<p align="center">
  <a href="http://nestjs.com/" target="blank"><img src="https://nestjs.com/img/logo-small.svg" width="120" alt="Nest Logo" /></a>
</p>

[circleci-image]: https://img.shields.io/circleci/build/github/nestjs/nest/master?token=abc123def456
[circleci-url]: https://circleci.com/gh/nestjs/nest

  <p align="center">A progressive <a href="http://nodejs.org" target="_blank">Node.js</a> framework for building efficient and scalable server-side applications.</p>
    <p align="center">
<a href="https://www.npmjs.com/~nestjscore" target="_blank"><img src="https://img.shields.io/npm/v/@nestjs/core.svg" alt="NPM Version" /></a>
<a href="https://www.npmjs.com/~nestjscore" target="_blank"><img src="https://img.shields.io/npm/l/@nestjs/core.svg" alt="Package License" /></a>
<a href="https://www.npmjs.com/~nestjscore" target="_blank"><img src="https://img.shields.io/npm/dm/@nestjs/common.svg" alt="NPM Downloads" /></a>
<a href="https://circleci.com/gh/nestjs/nest" target="_blank"><img src="https://img.shields.io/circleci/build/github/nestjs/nest/master" alt="CircleCI" /></a>
<a href="https://discord.gg/G7Qnnhy" target="_blank"><img src="https://img.shields.io/badge/discord-online-brightgreen.svg" alt="Discord"/></a>
<a href="https://opencollective.com/nest#backer" target="_blank"><img src="https://opencollective.com/nest/backers/badge.svg" alt="Backers on Open Collective" /></a>
<a href="https://opencollective.com/nest#sponsor" target="_blank"><img src="https://opencollective.com/nest/sponsors/badge.svg" alt="Sponsors on Open Collective" /></a>
  <a href="https://paypal.me/kamilmysliwiec" target="_blank"><img src="https://img.shields.io/badge/Donate-PayPal-ff3f59.svg" alt="Donate us"/></a>
    <a href="https://opencollective.com/nest#sponsor"  target="_blank"><img src="https://img.shields.io/badge/Support%20us-Open%20Collective-41B883.svg" alt="Support us"></a>
  <a href="https://twitter.com/nestframework" target="_blank"><img src="https://img.shields.io/twitter/follow/nestframework.svg?style=social&label=Follow" alt="Follow us on Twitter"></a>
</p>
  <!--[![Backers on Open Collective](https://opencollective.com/nest/backers/badge.svg)](https://opencollective.com/nest#backer)
  [![Sponsors on Open Collective](https://opencollective.com/nest/sponsors/badge.svg)](https://opencollective.com/nest#sponsor)-->

## Description

[Nest](https://github.com/nestjs/nest) framework TypeScript starter repository.

## Project setup

### Cloudflare R2 image storage

Set `STORAGE_S3_URL` (your Cloudflare R2 S3 endpoint), `STORAGE_ACCESS_KEY`,
and `STORAGE_SECRET_KEY` in `.env`. For this deployment, set:

```env
BUCKET=airpix
STORAGE_PUBLIC_URL=https://pub-455fef85d2d74e608a2dbc4c2e2a5fbe.r2.dev
```

`BUCKET` is the preferred explicit R2 bucket name; `STORAGE_BUCKET_NAME`
remains a supported fallback. The bucket suffix in `STORAGE_S3_URL` is
used only if neither variable is configured. Prefer the account/region
S3 endpoint without a bucket suffix, and never append `/airpix` to
`STORAGE_PUBLIC_URL`. The public domain must be enabled for the `airpix`
bucket in the Cloudflare R2 dashboard. R2 takes priority over `MINIO_*`.
Startup checks the bucket and creates it if missing; creation requires bucket
admin permission. Existing buckets only need object read/write access.

Single, batch, admin, and external API file uploads keep their existing response
formats. Without `STORAGE_PUBLIC_URL`, returned URLs stream from R2 through
`GET /image/file/:fileName?token=...`. Each permanent URL contains a signature
restricted to its object; missing or invalid signatures return 404. Keep
`STORAGE_URL_SECRET` stable (it defaults to `STORAGE_SECRET_KEY`) to preserve
these URLs across credential changes. Set `PUBLIC_API_URL` to your reachable
backend origin in production; otherwise the upload request origin is used.

For direct CDN image delivery, optionally set `STORAGE_PUBLIC_URL` to an enabled
R2 public bucket domain, such as `https://images.example.com`, without appending
the bucket name. The S3 API URL is not a public image URL. Public domains must be
configured in Cloudflare; R2 does not support S3 bucket policies. See
[Cloudflare public bucket docs](https://developers.cloudflare.com/r2/buckets/public-buckets/).
Existing MinIO files are not migrated automatically.

### Direct uploads with presigned URLs

The frontend and mobile app upload file bytes directly to R2. The backend only
handles upload authorization and event/profile metadata:

1. Send authenticated JSON to `POST /image/presign`:
   `{ "fileName": "photo.jpg", "contentType": "image/jpeg", "size": 12345 }`.
2. Send the raw file with `PUT` to the returned `uploadUrl`, using the returned
   `headers`. Do not use multipart encoding, app auth headers, or cookies on R2.
   The actual file length must match `size`; the signature binds both length and
   content type. URLs expire after 15 minutes; files are limited to 256 MiB.
3. After PUT succeeds, save the returned permanent `url` using the existing
   event/profile/branding/retouch endpoint. Never store the expiring `uploadUrl`.

`POST /image/presign/batch` accepts `{ "files": [ ... ] }` (up to 100 metadata
objects) and returns ordered `uploads`. `POST /image/presign-admin` requires the
admin role. Mobile batch transfers use three concurrent streams; camera queue
progress, cancellation, durable retries, and event registration are preserved.

External API clients can request `POST /v1/upload/presign` using `x-api-key`,
including `eventId` and `idempotencyKey` alongside the file metadata, upload to
R2, then register the permanent URL through `POST /v1/upload`.

The `airpix` bucket must allow browser CORS for your frontend origin, method `PUT`,
and header `Content-Type`. Configure its own CORS rules in Cloudflare as needed.
See [Cloudflare presigned URL docs](https://developers.cloudflare.com/r2/api/s3/presigned-urls/)
and [R2 CORS docs](https://developers.cloudflare.com/r2/buckets/cors/).

```bash
$ npm install
```

## Compile and run the project

```bash
# development
$ npm run start

# watch mode
$ npm run start:dev

# production mode
$ npm run start:prod
```

## Run tests

```bash
# unit tests
$ npm run test

# e2e tests
$ npm run test:e2e

# test coverage
$ npm run test:cov
```

## Deployment

When you're ready to deploy your NestJS application to production, there are some key steps you can take to ensure it runs as efficiently as possible. Check out the [deployment documentation](https://docs.nestjs.com/deployment) for more information.

If you are looking for a cloud-based platform to deploy your NestJS application, check out [Mau](https://mau.nestjs.com), our official platform for deploying NestJS applications on AWS. Mau makes deployment straightforward and fast, requiring just a few simple steps:

```bash
$ npm install -g @nestjs/mau
$ mau deploy
```

With Mau, you can deploy your application in just a few clicks, allowing you to focus on building features rather than managing infrastructure.

## Resources

Check out a few resources that may come in handy when working with NestJS:

- Visit the [NestJS Documentation](https://docs.nestjs.com) to learn more about the framework.
- For questions and support, please visit our [Discord channel](https://discord.gg/G7Qnnhy).
- To dive deeper and get more hands-on experience, check out our official video [courses](https://courses.nestjs.com/).
- Deploy your application to AWS with the help of [NestJS Mau](https://mau.nestjs.com) in just a few clicks.
- Visualize your application graph and interact with the NestJS application in real-time using [NestJS Devtools](https://devtools.nestjs.com).
- Need help with your project (part-time to full-time)? Check out our official [enterprise support](https://enterprise.nestjs.com).
- To stay in the loop and get updates, follow us on [X](https://x.com/nestframework) and [LinkedIn](https://linkedin.com/company/nestjs).
- Looking for a job, or have a job to offer? Check out our official [Jobs board](https://jobs.nestjs.com).

## Support

Nest is an MIT-licensed open source project. It can grow thanks to the sponsors and support by the amazing backers. If you'd like to join them, please [read more here](https://docs.nestjs.com/support).

## Stay in touch

- Author - [Kamil Myśliwiec](https://twitter.com/kammysliwiec)
- Website - [https://nestjs.com](https://nestjs.com/)
- Twitter - [@nestframework](https://twitter.com/nestframework)

## License

Nest is [MIT licensed](https://github.com/nestjs/nest/blob/master/LICENSE).
