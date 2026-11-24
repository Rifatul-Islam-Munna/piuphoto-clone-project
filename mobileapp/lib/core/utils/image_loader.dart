import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_avif/flutter_avif.dart';

class UrlHelper {
  UrlHelper._();

  static String fixLocalUrl(String? url) {
    if (url == null || url.isEmpty) return '';
    if (url.startsWith('https://')) return url;
    return url.replaceAll('localhost', '10.0.2.2');
  }
}

class ImageLoader {
  static bool isAvifUrl(String url) {
    final parsed = Uri.tryParse(url);
    final lower = url.toLowerCase();
    return lower.contains('format(avif)') ||
        lower.contains('format%28avif%29') ||
        parsed?.queryParameters['format']?.toLowerCase() == 'avif' ||
        (parsed?.path.toLowerCase().endsWith('.avif') ?? false);
  }

  static Widget loadImage(
    String? imageUrl, {
    String? fallbackUrl,
    double? width,
    double? height,
    BoxFit fit = BoxFit.cover,
    Widget? placeholder,
    Widget? errorWidget,
    BorderRadius? borderRadius,
  }) {
    final cleanUrl = UrlHelper.fixLocalUrl(imageUrl);

    if (cleanUrl.isEmpty) {
      return errorWidget ?? _buildErrorWidget();
    }

    final isAvif = isAvifUrl(cleanUrl);
    Widget failed() {
      final fallback = UrlHelper.fixLocalUrl(fallbackUrl);
      if (fallback.isNotEmpty && fallback != cleanUrl) {
        return loadImage(
          fallback,
          width: width,
          height: height,
          fit: fit,
          placeholder: placeholder,
          errorWidget: errorWidget,
        );
      }
      return errorWidget ?? _buildErrorWidget();
    }

    Widget image = isAvif
        ? CachedNetworkAvifImage(
            cleanUrl,
            width: width,
            height: height,
            fit: fit,
            frameBuilder: (context, child, frame, sync) => frame != null || sync
                ? child
                : (placeholder ?? _buildPlaceholder()),
            errorBuilder: (context, error, stack) => failed(),
          )
        : CachedNetworkImage(
            imageUrl: cleanUrl,
            width: width,
            height: height,
            fit: fit,
            placeholder: (context, url) => placeholder ?? _buildPlaceholder(),
            errorWidget: (context, url, error) => failed(),
            memCacheWidth: width != null && width.isFinite && width > 0
                ? width.toInt()
                : null,
            memCacheHeight: height != null && height.isFinite && height > 0
                ? height.toInt()
                : null,
          );

    if (borderRadius != null) {
      return ClipRRect(borderRadius: borderRadius, child: image);
    }

    return image;
  }

  static Widget loadImageCircle(
    String? imageUrl, {
    double? size,
    BoxFit fit = BoxFit.cover,
    Widget? placeholder,
    Widget? errorWidget,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(shape: BoxShape.circle),
      clipBehavior: Clip.antiAlias,
      child: loadImage(
        imageUrl,
        width: size,
        height: size,
        fit: fit,
        placeholder: placeholder,
        errorWidget: errorWidget,
      ),
    );
  }

  static Widget loadTemplateImage(
    String? imageUrl, {
    double? width,
    double? height,
    Widget? placeholder,
    Widget? errorWidget,
  }) {
    return loadImage(
      imageUrl,
      width: width,
      height: height,
      fit: BoxFit.cover,
      placeholder: placeholder,
      errorWidget: errorWidget ?? _buildTemplateErrorWidget(),
      borderRadius: BorderRadius.circular(12),
    );
  }

  static Widget _buildPlaceholder() {
    return Container(
      color: Colors.grey[200],
      child: const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  static Widget _buildErrorWidget() {
    return Container(
      color: Colors.grey[200],
      child: const Center(
        child: Icon(Icons.broken_image, color: Colors.grey, size: 32),
      ),
    );
  }

  static Widget _buildTemplateErrorWidget() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.grey[200],
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: const Center(
        child: Icon(Icons.image, color: Colors.grey, size: 40),
      ),
    );
  }

  static void clearCache() {
    imageCache.clear();
    imageCache.clearLiveImages();
  }
}
