import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:harvest/core/utils/platform/platform_tool.dart';

import '../config/app_config.dart';
import 'interceptors/auth_interceptor.dart';
import 'interceptors/response_interceptor.dart';

class DioClient {
  static final Dio dio = _createDio();

  static Dio _createDio() {
    final dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 30),
      ),
    );

    // Windows 下优化连接池配置
    if (PlatformTool.isWindows()) {
      (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
        final client = HttpClient();

        // 优化连接池配置，避免并发过多导致崩溃
        client.maxConnectionsPerHost = 10; // 限制每个主机的最大连接数
        client.idleTimeout = const Duration(seconds: 60); // 空闲连接超时

        return client;
      };
    }

    dio.interceptors.add(AuthInterceptor());
    dio.interceptors.add(ResponseInterceptor());

    return dio;
  }

  static void setBaseUrl(String baseUrl) {
    dio.options.baseUrl = baseUrl;
  }
}
