import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_strings.dart';
import '../theme/app_theme.dart';
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
  static const String currentVersion = '2.3.0';
  static const int currentVersionCode = 27;

  static const String rawVersionJsonUrl =
      'https://raw.githubusercontent.com/kumarnikki/Kisan-Mausam/main/version.json';
  static const String githubApiLatestUrl =
      'https://api.github.com/repos/kumarnikki/Kisan-Mausam/releases/latest';
  static const String defaultFallbackApkUrl =
      'https://github.com/kumarnikki/Kisan-Mausam/releases/download/v2.3.0/kisan-mausam-release.apk';

  static const MethodChannel _nativeChannel =
      MethodChannel('in.kishanmausam.kisan_mausam/native_alert');

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
        final data = response.data is Map
            ? response.data
            : Map<String, dynamic>.from(response.data);
        final remoteVersion = (data['version'] ?? '1.0.0').toString();
        final remoteCode = int.tryParse(data['versionCode']?.toString() ?? '1') ?? 1;
        final bool newer =
            isNewerVersion(remoteVersion, currentVersion) || remoteCode > currentVersionCode;

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
        final data = response.data is Map
            ? response.data
            : Map<String, dynamic>.from(response.data);
        final remoteVersion = (data['version'] ?? '1.0.0').toString();
        final remoteCode = int.tryParse(data['versionCode']?.toString() ?? '1') ?? 1;
        final bool newer =
            isNewerVersion(remoteVersion, currentVersion) || remoteCode > currentVersionCode;

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

  /// Resolve local cache file path for in-app APK download on Android
  static Future<String> getUpdateApkPath(String version) async {
    final cleanVer = version.replaceAll(RegExp(r'[^0-9A-Za-z._-]'), '_');
    try {
      if (!kIsWeb && Platform.isAndroid) {
        final nativePath = await _nativeChannel.invokeMethod<String>('getUpdateApkPath');
        if (nativePath != null && nativePath.isNotEmpty) {
          final parentDir = File(nativePath).parent.path;
          return '$parentDir/kisan-mausam-update-$cleanVer.apk';
        }
      }
    } catch (_) {}
    final sysTemp = Directory.systemTemp.path;
    return '$sysTemp/kisan-mausam-update-$cleanVer.apk';
  }

  /// Trigger native Android Package Installer via FileProvider without opening browser
  static Future<bool> installDownloadedApk(String filePath) async {
    try {
      if (!kIsWeb && Platform.isAndroid) {
        final launched = await _nativeChannel.invokeMethod<bool>(
          'installApk',
          {'filePath': filePath},
        );
        return launched == true;
      }
    } catch (_) {}
    return false;
  }

  /// Fallback browser launch only for non-Android platforms
  static Future<bool> launchUpdate(String apkUrl) async {
    final uri = Uri.parse(apkUrl);
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  /// Show the interactive In-App Download & Install Update Dialog
  static void showUpdateDialog(
    BuildContext context,
    AppUpdateInfo info, {
    bool dismissible = true,
    String lang = 'hi',
  }) {
    showDialog(
      context: context,
      barrierDismissible: dismissible && !info.isForceUpdate,
      builder: (ctx) => _InAppUpdateDialog(
        info: info,
        dismissible: dismissible && !info.isForceUpdate,
        lang: lang,
      ),
    );
  }
}

class _InAppUpdateDialog extends StatefulWidget {
  final AppUpdateInfo info;
  final bool dismissible;
  final String lang;

  const _InAppUpdateDialog({
    required this.info,
    required this.dismissible,
    required this.lang,
  });

  @override
  State<_InAppUpdateDialog> createState() => _InAppUpdateDialogState();
}

class _InAppUpdateDialogState extends State<_InAppUpdateDialog> {
  bool _isDownloading = false;
  bool _isCompleted = false;
  double _progress = 0.0;
  int _receivedBytes = 0;
  int _totalBytes = 0;
  String? _downloadedFilePath;
  String? _errorMessage;
  CancelToken? _cancelToken;

  final Dio _downloadDio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 10),
      followRedirects: true,
      maxRedirects: 8,
    ),
  );

  @override
  void dispose() {
    _cancelToken?.cancel('Dialog closed');
    super.dispose();
  }

  String _formatMb(int bytes) {
    if (bytes <= 0) return '0.0 MB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _startInAppDownloadAndInstall() async {
    if (kIsWeb || !Platform.isAndroid) {
      await UpdateService.launchUpdate(widget.info.apkUrl);
      return;
    }

    setState(() {
      _isDownloading = true;
      _isCompleted = false;
      _errorMessage = null;
      _progress = 0.0;
      _receivedBytes = 0;
      _totalBytes = 0;
    });

    try {
      final savePath = await UpdateService.getUpdateApkPath(widget.info.latestVersion);
      final targetFile = File(savePath);

      // If already downloaded completely in this session and > 5 MB, install directly
      if (_downloadedFilePath == savePath &&
          await targetFile.exists() &&
          await targetFile.length() > 5 * 1024 * 1024) {
        if (!mounted) return;
        setState(() {
          _isDownloading = false;
          _isCompleted = true;
          _progress = 1.0;
        });
        await UpdateService.installDownloadedApk(savePath);
        return;
      }

      if (await targetFile.exists()) {
        try {
          await targetFile.delete();
        } catch (_) {}
      }

      _cancelToken = CancelToken();
      await _downloadDio.download(
        widget.info.apkUrl,
        savePath,
        cancelToken: _cancelToken,
        deleteOnError: true,
        onReceiveProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _receivedBytes = received;
            _totalBytes = total;
            if (total > 0) {
              _progress = (received / total).clamp(0.0, 1.0);
            }
          });
        },
      );

      if (!mounted) return;

      final downloadedFile = File(savePath);
      if (!await downloadedFile.exists() || await downloadedFile.length() <= 0) {
        throw Exception('Empty APK file');
      }

      setState(() {
        _isDownloading = false;
        _isCompleted = true;
        _progress = 1.0;
        _downloadedFilePath = savePath;
      });

      final launched = await UpdateService.installDownloadedApk(savePath);
      if (!launched && mounted) {
        setState(() {
          _errorMessage = widget.lang == 'en'
              ? 'Could not open system installer. Tap Install Update below.'
              : 'इंस्टॉलर खोलने में समस्या। नीचे "अभी इंस्टॉल करें" दबाएं।';
        });
      }
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        if (!mounted) return;
        setState(() {
          _isDownloading = false;
          _errorMessage = null;
        });
        return;
      }
      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        _errorMessage = widget.lang == 'en'
            ? 'Download interrupted. Check internet connection and tap Retry.'
            : 'डाउनलोड रुक गया। इंटरनेट जांचें और पुनः प्रयास करें।';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        _errorMessage = widget.lang == 'en'
            ? 'Download failed. Please tap Retry.'
            : 'डाउनलोड विफल रहा। कृपया पुनः प्रयास करें।';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEn = widget.lang == 'en';
    final primaryColor = AppTheme.primaryActionColor(context);
    final percentText = '${(_progress * 100).toStringAsFixed(0)}%';

    return PopScope(
      canPop: widget.dismissible && !_isDownloading,
      child: AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.system_update_alt_rounded, color: primaryColor, size: 26),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppStrings.get('update_dialog_title', widget.lang),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary(context),
                    ),
                  ),
                  Text(
                    'v${widget.info.currentVersion} ➔ v${widget.info.latestVersion}',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: primaryColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.borderColor(context)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.new_releases_rounded, color: primaryColor, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          AppStrings.get('update_dialog_whats_new', widget.lang),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary(context),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.info.changelog,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.textSecondary(context),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // In-App Download Progress Section
              if (_isDownloading || _isCompleted) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: primaryColor.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              _isCompleted
                                  ? (isEn
                                      ? 'Update downloaded! Opening installer...'
                                      : 'अपडेट डाउनलोड पूरा! इंस्टॉलर खुल रहा है...')
                                  : (isEn
                                      ? 'Downloading update in-app...'
                                      : 'ऐप के अंदर अपडेट डाउनलोड हो रहा है...'),
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textPrimary(context),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _totalBytes > 0 ? percentText : '',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: primaryColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: _totalBytes > 0
                              ? _progress
                              : (_isCompleted ? 1.0 : null),
                          minHeight: 8,
                          backgroundColor: primaryColor.withValues(alpha: 0.15),
                          valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _totalBytes > 0
                            ? '${_formatMb(_receivedBytes)} / ${_formatMb(_totalBytes)}'
                            : (_receivedBytes > 0
                                ? _formatMb(_receivedBytes)
                                : (isEn ? 'Connecting to update server...' : 'अपडेट सर्वर से जुड़ रहा है...')),
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textSecondary(context),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],

              // Error message banner if download failed
              if (_errorMessage != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.dangerRed.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.dangerRed.withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, color: AppTheme.dangerRed, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],

              Row(
                children: [
                  const Icon(Icons.verified_user_rounded, color: AppTheme.infoBlue, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      AppStrings.get('update_dialog_data_safe', widget.lang),
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppTheme.textSecondary(context),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        actions: [
          if (_isDownloading) ...[
            if (widget.dismissible)
              TextButton(
                onPressed: () {
                  _cancelToken?.cancel('Cancelled by user');
                },
                child: Text(isEn ? 'Cancel' : 'रद्द करें'),
              ),
          ] else ...[
            if (widget.dismissible)
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(AppStrings.get('update_dialog_later', widget.lang)),
              ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryButtonFill(context),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: Icon(
                _isCompleted
                    ? Icons.install_mobile_rounded
                    : (_errorMessage != null ? Icons.refresh_rounded : Icons.system_update_alt_rounded),
                size: 18,
              ),
              label: Text(
                _isCompleted
                    ? (isEn ? 'Install Update Now' : 'अभी इंस्टॉल करें')
                    : (_errorMessage != null
                        ? (isEn ? 'Retry Download' : 'पुनः प्रयास करें')
                        : (isEn ? 'Download & Install' : 'अभी डाउनलोड व इंस्टॉल करें')),
              ),
              onPressed: () async {
                if (_isCompleted && _downloadedFilePath != null) {
                  await UpdateService.installDownloadedApk(_downloadedFilePath!);
                } else {
                  await _startInAppDownloadAndInstall();
                }
              },
            ),
          ],
        ],
      ),
    );
  }
}
