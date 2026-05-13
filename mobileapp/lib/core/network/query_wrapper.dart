import 'package:mobileapp/core/network/dio_helper.dart';
import 'package:mobileapp/core/network/failure.dart';
import 'package:cached_query/cached_query.dart';
import 'package:cached_query_flutter/cached_query_flutter.dart';
import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';

// ─── HTTP Method ──────────────────────────────────────────────
Query<Either<Failure, T>> useQueryWrapper<T>({
  required String key,
  required String url,
  required T Function(dynamic json) fromJson,
  Map<String, dynamic>? queryParams,
  Duration cacheDuration = const Duration(minutes: 5),
  Duration storageDuration = const Duration(hours: 1),
  bool refetchOnResume = true,
  bool refetchOnConnection = true,
}) {
  return Query<Either<Failure, T>>(
    key: key,
    queryFn: () =>
        _getRequest<T>(url: url, fromJson: fromJson, queryParams: queryParams),
    config: QueryConfig(
      cacheDuration: cacheDuration,
      storageDuration: storageDuration,
      refetchOnResume: refetchOnResume,
      refetchOnConnection: refetchOnConnection,
    ),
  );
}

/// Internal GET request with dartz Either
Future<Either<Failure, T>> _getRequest<T>({
  required String url,
  required T Function(dynamic json) fromJson,
  Map<String, dynamic>? queryParams,
}) async {
  try {
    final response = await DioHelper.dio.get(url, queryParameters: queryParams);
    return Right(fromJson(response.data));
  } on DioException catch (e) {
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout) {
      return Left(NetworkFailure('No internet connection'));
    }
    return Left(
      ServerFailure(
        e.response?.data?['message'] ?? 'Server error',
        statusCode: e.response?.statusCode,
      ),
    );
  } catch (e) {
    return Left(ServerFailure('Unexpected error: $e'));
  }
}

// Add this public function alongside useQueryWrapper
// This is for imperative calls (pagination, StatefulWidget)
Future<Either<Failure, T>> makeGetRequest<T>({
  required String url,
  required T Function(dynamic json) fromJson,
  Map<String, dynamic>? queryParams,
}) => _getRequest<T>(url: url, fromJson: fromJson, queryParams: queryParams);
//   ↑ reuses the same private _getRequest — no code duplication
