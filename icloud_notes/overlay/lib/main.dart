import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _ensureWebViewEnvironment();
  runApp(const NotesApp());
}

Future<void> _ensureWebViewEnvironment() async {
  if (Platform.isAndroid) {
    await AndroidInAppWebViewController.setWebContentsDebuggingEnabled(true);
    var swAvailable = await AndroidWebViewFeature.isFeatureSupported(AndroidWebViewFeature.SERVICE_WORKER_BASIC_USAGE);
    var swIntercept = await AndroidWebViewFeature.isFeatureSupported(AndroidWebViewFeature.SERVICE_WORKER_SHOULD_INTERCEPT_REQUEST);
    if (swAvailable && swIntercept) {
      AndroidServiceWorkerController serviceWorkerController = AndroidServiceWorkerController.instance();
      serviceWorkerController.setServiceWorkerClient(AndroidServiceWorkerClient(shouldInterceptRequest: (request) async {
        return null; // Let iCloud handle its own SW
      }));
    }
  }
}

class NotesApp extends StatelessWidget {
  const NotesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'iCloud Notes',
      themeMode: ThemeMode.system,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.amber),
        useMaterial3: true,
      ),
      darkTheme: ThemeData.dark(useMaterial3: true),
      home: const NotesHomePage(),
    );
  }
}

class NotesHomePage extends StatefulWidget {
  const NotesHomePage({super.key});

  @override
  State<NotesHomePage> createState() => _NotesHomePageState();
}

class _NotesHomePageState extends State<NotesHomePage> {
  final String startUrl = 'https://www.icloud.com/notes';
  InAppWebViewController? _controller;
  PullToRefreshController? _ptr;
  String _title = 'iCloud Notes';
  double _progress = 0.0;
  bool _online = true;
  late StreamSubscription _connSub;
  String? _cachedSnapshotPath; // offline snapshot HTML

  static const String lastSnapshotKey = 'last_snapshot_path_v1';
  static const String lastUrlKey = 'last_url_v1';

  final String spoofedUserAgent =
      'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';

  @override
  void initState() {
    super.initState();
    _ptr = PullToRefreshController(
      options: PullToRefreshOptions(color: Colors.amber),
      onRefresh: () async {
        if (_controller != null) {
          if (Platform.isAndroid) {
            _controller!.reload();
          } else if (Platform.isIOS) {
            _controller!.loadUrl(urlRequest: URLRequest(url: await _controller!.getUrl()));
          }
        }
      },
    );

    _initConnectivity();
    _loadLastSnapshot();
  }

  Future<void> _initConnectivity() async {
    final initial = await Connectivity().checkConnectivity();
    _online = initial != ConnectivityResult.none;
    _connSub = Connectivity().onConnectivityChanged.listen((result) {
      final nowOnline = result != ConnectivityResult.none;
      if (nowOnline != _online) {
        setState(() => _online = nowOnline);
        if (nowOnline && _controller != null) {
          _controller!.reload();
        }
      }
    });
  }

  Future<void> _loadLastSnapshot() async {
    final prefs = await SharedPreferences.getInstance();
    _cachedSnapshotPath = prefs.getString(lastSnapshotKey);
    setState(() {});
  }

  @override
  void dispose() {
    _connSub.cancel();
    super.dispose();
  }

  Future<String> _snapshotDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final snap = Directory('${dir.path}/snapshots');
    if (!await snap.exists()) await snap.create(recursive: true);
    return snap.path;
  }

  Future<void> _saveHtmlSnapshot(String html) async {
    try {
      final dir = await _snapshotDir();
      final file = File('$dir/notes_${DateTime.now().millisecondsSinceEpoch}.html');
      await file.writeAsString(html, flush: true);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(lastSnapshotKey, file.path);

      final url = await _controller?.getUrl();
      if (url != null) await prefs.setString(lastUrlKey, url.toString());

      // Extract a crude title from HTML (first <title> or first <h1>)
      String? title;
      final match = RegExp(r'<title>(.*?)</title>', caseSensitive: false).firstMatch(html);
      if (match != null) {
        title = match.group(1)?.trim();
      } else {
        final h1 = RegExp(r'<h1[^>]*>(.*?)</h1>', caseSensitive: false).firstMatch(html);
        title = h1?.group(1)?.trim();
      }
      title ??= "📒 iCloud Notes";
      await prefs.setString("last_snapshot_title", title);

      // Trigger widget refresh (via platform channel)
      const platform = MethodChannel('icloud_notes_widget_channel');
      try {
        await platform.invokeMethod('refreshWidgets');
      } catch (_) {}

      setState(() => _cachedSnapshotPath = file.path);
    } catch (_) {}
  }

  Future<void> _openInBrowser(Uri url) async {
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) return;
  }

  NavigationActionPolicy _extLinkPolicy(NavigationAction action) {
    final uri = action.request.url;
    if (uri == null) return NavigationActionPolicy.ALLOW;
    final host = uri.host;
    if (host.endsWith('icloud.com') || host.endsWith('apple.com')) {
      return NavigationActionPolicy.ALLOW;
    } else {
      _openInBrowser(uri);
      return NavigationActionPolicy.CANCEL;
    }
  }

  @override
  Widget build(BuildContext context) {
    final offline = !_online;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Theme.of(context).brightness == Brightness.dark
            ? Brightness.light
            : Brightness.dark,
      ),
      child: Scaffold(
        appBar: AppBar(
          title: Text(_title, overflow: TextOverflow.ellipsis),
          centerTitle: true,
          actions: [
            IconButton(
              tooltip: 'Open in browser',
              icon: const Icon(Icons.open_in_new),
              onPressed: () => _openInBrowser(Uri.parse(startUrl)),
            ),
          ],
        ),
        body: SafeArea(
          child: Stack(
            children: [
              if (!offline)
                InAppWebView(
                  initialUrlRequest: URLRequest(url: WebUri(startUrl)),
                  initialOptions: InAppWebViewGroupOptions(
                    crossPlatform: InAppWebViewOptions(
                      javaScriptEnabled: true,
                      useShouldOverrideUrlLoading: true,
                      mediaPlaybackRequiresUserGesture: true,
                      userAgent: spoofedUserAgent,
                      transparentBackground: false,
                      cacheEnabled: true,
                      disableContextMenu: false,
                    ),
                    android: AndroidInAppWebViewOptions(
                      builtInZoomControls: false,
                      thirdPartyCookiesEnabled: true,
                      supportMultipleWindows: true,
                      useShouldInterceptRequest: false,
                      mixedContentMode: AndroidMixedContentMode.MIXED_CONTENT_COMPATIBILITY_MODE,
                    ),
                    ios: IOSInAppWebViewOptions(allowsInlineMediaPlayback: true),
                  ),
                  pullToRefreshController: _ptr,
                  onWebViewCreated: (c) => _controller = c,
                  shouldOverrideUrlLoading: (controller, action) async {
                    return _extLinkPolicy(action);
                  },
                  onTitleChanged: (c, t) => setState(() => _title = t ?? 'iCloud Notes'),
                  onProgressChanged: (c, p) {
                    setState(() => _progress = p / 100.0);
                    if (p == 100) _ptr?.endRefreshing();
                  },
                  onLoadStop: (c, url) async {
                    _ptr?.endRefreshing();
                    try {
                      final html = await c.evaluateJavascript(source: 'document.documentElement.outerHTML');
                      if (html is String && html.length > 5000) {
                        _saveHtmlSnapshot(html);
                      }
                    } catch (_) {}
                  },
                  onDownloadStartRequest: (c, req) async {
                    if (req.url != null) _openInBrowser(req.url!);
                  },
                )
              else
                _OfflineView(snapshotPath: _cachedSnapshotPath),

              if (_progress > 0 && _progress < 1)
                LinearProgressIndicator(value: _progress),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          icon: const Icon(Icons.refresh),
          label: Text(_online ? 'Reload' : 'Retry Online'),
          onPressed: () async {
            if (_online) {
              await _controller?.reload();
            } else {
              final now = await Connectivity().checkConnectivity();
              setState(() => _online = now != ConnectivityResult.none);
            }
          },
        ),
      ),
    );
  }
}

class _OfflineView extends StatelessWidget {
  final String? snapshotPath;
  const _OfflineView({required this.snapshotPath});

  @override
  Widget build(BuildContext context) {
    if (snapshotPath == null) {
      return _EmptyOfflineState();
    }
    final uri = Uri.file(snapshotPath!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Row(
            children: [
              const Icon(Icons.cloud_off),
              const SizedBox(width: 8),
              Expanded(child: Text('Offline preview • Last saved snapshot')),
            ],
          ),
        ),
        Expanded(
          child: InAppWebView(
            initialFile: uri.toFilePath(),
            initialOptions: InAppWebViewGroupOptions(
              crossPlatform: InAppWebViewOptions(javaScriptEnabled: false),
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyOfflineState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sticky_note_2_outlined, size: 72),
            const SizedBox(height: 12),
            Text(
              'No offline snapshot yet',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Open the app while online once. We\'ll save a lightweight snapshot so you can preview your notes when offline.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
