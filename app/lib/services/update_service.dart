import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_strings.dart';
import 'api_service.dart';

class AppUpdateInfo {
  final bool hasUpdate;
  final String currentVersion;
  final String latestVersion;
  final int latestVersionCode;
  final String releaseName;
  final String changelog;
  final String apkUrl;
  final String? githubReleaseUrl;
  final bool isForceUpdate;

  const AppUpdateInfo({
    required this.hasUpdate,
    required this.currentVersion,
    required this.latestVersion,
    required this.latestVersionCode,
    required this.releaseName,
    required this.changelog,
    required this.apkUrl,
    this.githubReleaseUrl,
    this.isForceUpdate = false,
  });
}

class UpdateService {
  static const String currentVersion = '1.1.5';
  static const int currentVersionCode = 15;

  static const String rawVersionJsonUrl =
      'https://raw.githubusercontent.com/kumarnikki/Kisan-Mausam/main/version.json';
  static const String githubApiLatestUrl =
      'https://api.github.com/repos/kumarnikki/Kisan-Mausam/releases/latest';
  static const String defaultFallbackApkUrl =
      'https://github.com/kumarnikki/Kisan-Mausam/releases/download/v1.0.0/kisan-mausam-release.apk';

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 6),
      receiveTimeout: const Duration(seconds: 6),
    ),
  );

  /// Compare two semantic version strings like "1.0.1" and "1.0.0"
  static bool isNewerVersion(String latest, String current) {
    try {
      final cleanLatest = latest.replaceAll(RegExp(r'[^0-9.]'), '');
      final cleanCurrent = current.replaceAll(RegExp(r'[^0-9.]'), '');
      final lParts = cleanLatest.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final cParts = cleanCurrent.split('.').map((e) => int.tryParse(e) ?? 0).toList();

      final maxLen = lParts.length > cParts.length ? lParts.length : cParts.length;
      for (int i = 0; i < maxLen; i++) {
        final l = i < lParts.length ? lParts[i] : 0;
        final c = i < cParts.length ? cParts[i] : 0;
        if (l > c) return true;
        if (l < c) return false;
      }
      return false;
    } catch (_) {
      return latest.trim() != current.trim() && latest.isNotEmpty;
    }
  }

  /// Check for updates from raw GitHub repo, custom backend, or GitHub Releases API
  static Future<AppUpdateInfo> checkForUpdate() async {
    // 1. Try raw version.json (Fastest, zero rate limit, instant update after push)
    try {
      final response = await _dio.get(
        rawVersionJsonUrl,
        options: Options(
          headers: {'Cache-Control': 'no-cache', 'Pragma': 'no-cache'},
        ),
      );
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data is Map ? response.data : Map<String, dynamic>.from(response.data);
        final remoteVersion = (data['version'] ?? '1.0.0').toString();
        final remoteCode = int.tryParse(data['versionCode']?.toString() ?? '1') ?? 1;
        final bool newer = isNewerVersion(remoteVersion, currentVersion) || remoteCode > currentVersionCode;

        return AppUpdateInfo(
          hasUpdate: newer,
          currentVersion: currentVersion,
          latestVersion: remoteVersion,
          latestVersionCode: remoteCode,
          releaseName: data['releaseName'] ?? 'Kisan Mausam v$remoteVersion',
          changelog: data['changelog'] ?? '• नवीनतम बग फिक्स और मौसम व एआई सुधार',
          apkUrl: data['apkUrl'] ?? defaultFallbackApkUrl,
          githubReleaseUrl: data['githubReleaseUrl'],
          isForceUpdate: data['isForce'] == true,
        );
      }
    } catch (_) {
      // Continue to next fallback
    }

    // 2. Try configured backend /api/v1/app/version
    try {
      final backendUrl = ApiService.backendBaseUrl;
      final response = await _dio.get('$backendUrl/api/v1/app/version');
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data is Map ? response.data : Map<String, dynamic>.from(response.data);
        final remoteVersion = (data['version'] ?? '1.0.0').toString();
        final remoteCode = int.tryParse(data['versionCode']?.toString() ?? '1') ?? 1;
        final bool newer = isNewerVersion(remoteVersion, currentVersion) || remoteCode > currentVersionCode;

        return AppUpdateInfo(
          hasUpdate: newer,
          currentVersion: currentVersion,
          latestVersion: remoteVersion,
          latestVersionCode: remoteCode,
          releaseName: data['releaseName'] ?? 'Kisan Mausam v$remoteVersion',
          changelog: data['changelog'] ?? '• बैकएंड सर्वर और मॉडल सुधार',
          apkUrl: data['apkUrl'] ?? defaultFallbackApkUrl,
          githubReleaseUrl: data['githubReleaseUrl'],
          isForceUpdate: data['isForce'] == true,
        );
      }
    } catch (_) {
      // Continue to GitHub API
    }

    // 3. Fallback to GitHub Releases API
    try {
      final response = await _dio.get(githubApiLatestUrl);
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        final tagName = (data['tag_name'] ?? 'v1.0.0').toString();
        final remoteVersion = tagName.replaceAll(RegExp(r'^[vV]'), '');
        final bool newer = isNewerVersion(remoteVersion, currentVersion);

        String apkUrl = defaultFallbackApkUrl;
        final assets = data['assets'] as List?;
        if (assets != null) {
          for (final asset in assets) {
            final name = asset['name'] as String? ?? '';
            if (name.endsWith('.apk')) {
              apkUrl = asset['browser_download_url'] ?? apkUrl;
              break;
            }
          }
        }

        return AppUpdateInfo(
          hasUpdate: newer,
          currentVersion: currentVersion,
          latestVersion: remoteVersion,
          latestVersionCode: 1,
          releaseName: data['name'] ?? 'Kisan Mausam $tagName',
          changelog: (data['body'] as String? ?? '').isNotEmpty
              ? data['body'] as String
              : '• नवीनतम कृषि व मौसम मॉडल सुधार',
          apkUrl: apkUrl,
          githubReleaseUrl: data['html_url'],
        );
      }
    } catch (_) {
      // Return current version (up to date)
    }

    return const AppUpdateInfo(
      hasUpdate: false,
      currentVersion: currentVersion,
      latestVersion: currentVersion,
      latestVersionCode: currentVersionCode,
      releaseName: 'Kisan Mausam v$currentVersion',
      changelog: 'ऐप नवीनतम संस्करण पर है।',
      apkUrl: defaultFallbackApkUrl,
    );
  }

  /// Launch APK download in system browser / download manager
  static Future<bool> launchUpdate(String apkUrl) async {
    final uri = Uri.parse(apkUrl);
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  /// Show the interactive Update Dialog
  static void showUpdateDialog(
    BuildContext context,
    AppUpdateInfo info, {
    bool dismissible = true,
    String lang = 'hi',
  }) {
    showDialog(
      context: context,
      barrierDismissible: dismissible,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF1B5E20).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.system_update, color: Color(0xFF1B5E20), size: 26),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppStrings.get('update_dialog_title', lang),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'v${info.currentVersion} ➔ v${info.latestVersion}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.green.shade800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.new_releases, color: Color(0xFF1B5E20), size: 16),
                      const SizedBox(width: 6),
                      Text(
                        AppStrings.get('update_dialog_whats_new', lang),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    info.changelog,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.verified_user, color: Colors.blue, size: 15),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    AppStrings.get('update_dialog_data_safe', lang),
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ),
              ],
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          if (dismissible)
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(AppStrings.get('update_dialog_later', lang)),
            ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1B5E20),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.download, size: 18),
            label: Text(AppStrings.get('update_dialog_now', lang)),
            onPressed: () async {
              Navigator.pop(ctx);
              final messenger = ScaffoldMessenger.of(context);
              messenger.showSnackBar(
                SnackBar(
                  content: Text(AppStrings.get('update_downloading_snack', lang)),
                  backgroundColor: const Color(0xFF1B5E20),
                  duration: const Duration(seconds: 4),
                ),
              );
              await launchUpdate(info.apkUrl);
            },
          ),
        ],
      ),
    );
  }
}
