import 'package:mobileapp/core/network/dio_helper.dart';
import 'package:mobileapp/core/network/failure.dart';
import 'package:mobileapp/utilities/app_toast.dart';
import 'package:cached_query/cached_query.dart';
import 'package:cached_query_flutter/cached_query_flutter.dart';
import 'package:dio/dio.dart';

// ─── HTTP Method ──────────────────────────────────────────────
enum HttpMethod { post, patch, delete }

// ─── Mutation Config ──────────────────────────────────────────
class MutationConfig<TData, TVariables> {
  final String url;
  final HttpMethod method;
  final String? mutationKey;
  final String? successMessage;
  final TData Function(dynamic json)? fromJson;
  final void Function(TData data)? onSuccess;
  final void Function(Failure failure)? onError;

  const MutationConfig({
    required this.url,
    required this.method,
    this.mutationKey,
    this.successMessage,
    this.fromJson,
    this.onSuccess,
    this.onError,
  });
}

// ─── Result wrapper (mirrors your { data, error } response) ───
class MutationResult<TData> {
  final TData? data;
  final Failure? error;

  const MutationResult({this.data, this.error});

  bool get isSuccess => data != null && error == null;
}

// ─── The main wrapper — your useCommonMutationApi ─────────────
Mutation<MutationResult<TData>, TVariables> useCommonMutationApi<
  TData,
  TVariables
>({required MutationConfig<TData, TVariables> config}) {
  return Mutation<MutationResult<TData>, TVariables>(
    key: config.mutationKey ?? config.url,
    mutationFn: (variables) => _executeMutation<TData, TVariables>(
      config: config,
      variables: variables,
    ),
    onSuccess: (result, arg) {
      if (result.isSuccess) {
        // ✅ show success toast
        AppToast.success(config.successMessage ?? 'Success!');
        config.onSuccess?.call(result.data as TData);
      } else {
        // ❌ server returned error inside body
        AppToast.error(result.error?.message ?? 'Unknown error');
        config.onError?.call(
          result.error ?? const ServerFailure('Unknown error'),
        );
      }
    },
    onError: (error, arg, fallback) {
      final message = error is Failure ? error.message : error.toString();
      AppToast.error(message);
      config.onError?.call(ServerFailure(message));
    },
  );
}

// ─── Internal executor — picks POST / PATCH / DELETE ─────────
Future<MutationResult<TData>> _executeMutation<TData, TVariables>({
  required MutationConfig<TData, TVariables> config,
  required TVariables variables,
}) async {
  try {
    Response response;

    switch (config.method) {
      case HttpMethod.post:
        response = await DioHelper.dio.post(config.url, data: variables);
        break;

      case HttpMethod.patch:
        response = await DioHelper.dio.patch(config.url, data: variables);
        break;

      case HttpMethod.delete:
        // mirrors: `${url}?id=${id}`
        final id = variables is String
            ? variables
            : (variables as dynamic)?.id?.toString();
        response = await DioHelper.dio.delete(
          config.url,
          queryParameters: id != null ? {'id': id} : null,
        );
        break;
    }

    final parsed = config.fromJson != null
        ? config.fromJson!(response.data)
        : response.data as TData;

    return MutationResult(data: parsed);
  } on DioException catch (e) {
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout) {
      return MutationResult(
        error: const NetworkFailure('No internet connection'),
      );
    }
    final data = e.response?.data;
    final rawMessage = data?['message'];
    final message = rawMessage is Map
        ? rawMessage['message']?.toString() ?? 'Server error'
        : rawMessage?.toString() ?? 'Server error';
    return MutationResult(
      error: ServerFailure(message, statusCode: e.response?.statusCode),
    );
  } catch (e) {
    return MutationResult(error: ServerFailure('Unexpected error: $e'));
  }
}
