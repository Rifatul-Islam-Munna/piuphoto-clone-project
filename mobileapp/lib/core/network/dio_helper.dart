import 'dart:async';
import 'package:dio/dio.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:mobileapp/core/storage/user_storage.dart';

class DioHelper {
  static Dio? _dio;
  static bool _isRedirecting = false;
  static Future<void> Function()? _onUnauthorized;

  static Dio get dio {
    if (_dio == null) {
      throw Exception('Dio is not initialized. Call DioHelper.init() first.');
    }
    return _dio!;
  }

  static String get baseUrl {
    final raw = dotenv.env['API_URL'] ?? '';
    final cleaned = raw.split('#').first.trim();
    return cleaned.isNotEmpty ? cleaned : 'http://10.0.2.2:4000';
  }

  static void init() {
    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        receiveDataWhenStatusError: true,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 60),
        contentType: Headers.jsonContentType,
      ),
    );

    _dio!.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await UserStorage.getAccessToken();

          if (token != null && token.isNotEmpty) {
            options.headers['access_token'] = token;
          }

          handler.next(options);
        },
        onError: (DioException error, handler) async {
          if (error.response?.statusCode == 401 && !_isRedirecting) {
            _isRedirecting = true;
            await UserStorage.clear();
            final onUnauthorized = _onUnauthorized;
            if (onUnauthorized != null) {
              await onUnauthorized();
            }
            _isRedirecting = false;
          }

          handler.next(error);
        },
      ),
    );

    _dio!.interceptors.add(
      PrettyDioLogger(
        requestHeader: true,
        requestBody: true,
        responseHeader: false,
        responseBody: true,
        compact: true,
        maxWidth: 90,
      ),
    );
  }

  static void setUnauthorizedHandler(Future<void> Function() handler) {
    _onUnauthorized = handler;
  }

  static Future<Response> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    return await dio.get(
      path,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
  }

  static Future<Response> post(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    return await dio.post(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
  }

  static Future<Response> put(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    return await dio.put(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
  }

  static Future<Response> delete(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    return await dio.delete(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
  }

  static Future<void> setAccessToken(String token) async {
    await UserStorage.saveAccessToken(token);
    _dio?.options.headers['access_token'] = token;
  }

  static Future<String?> getAccessToken() async {
    return await UserStorage.getAccessToken();
  }

  static Future<void> clearAccessToken() async {
    await UserStorage.clear();
    _dio?.options.headers.remove('access_token');
  }
}
