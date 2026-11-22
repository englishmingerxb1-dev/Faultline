// FaultLine - Android app for the FaultLine ETS2 tablet.
// Finds the PC running run_faultline.bat on the same Wi-Fi and shows the
// tablet full-screen, with the screen kept awake while you drive.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

const int kDefaultPort = 8080;
const String kDefaultHost = '192.168.0.143:8080';
const Color kBg = Color(0xFF0F1216);
const Color kAmber = Color(0xFFFFB020);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const FaultLineApp());
}

class FaultLineApp extends StatelessWidget {
  const FaultLineApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FaultLine',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kBg,
        colorScheme: ColorScheme.fromSeed(
            seedColor: kAmber, brightness: Brightness.dark),
      ),
      home: const HomePage(),
    );
  }
}

enum Stage { checking, scanning, setup, connected, lost }

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Stage stage = Stage.checking;
  String host = kDefaultHost;
  String message = '';
  int scanned = 0;
  WebViewController? web;
  final TextEditingController field = TextEditingController();

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    field.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final prefs = await SharedPreferences.getInstance();
    host = prefs.getString('host') ?? kDefaultHost;
    field.text = host;
    await _connect(scanIfMissing: true);
  }

  Future<void> _connect({bool scanIfMissing = false}) async {
    setState(() {
      stage = Stage.checking;
      message = 'Looking for FaultLine at $host ...';
    });
    if (await probe(host) != null) {
      _open();
      return;
    }
    if (scanIfMissing) {
      await _scan();
    } else {
      setState(() {
        stage = Stage.setup;
        message = "Can't reach FaultLine at $host.";
      });
    }
  }

  Future<void> _scan() async {
    setState(() {
      stage = Stage.scanning;
      scanned = 0;
      message = 'Searching your Wi-Fi for the PC ...';
    });
    final found = await findPc(kDefaultPort, (n) {
      if (mounted) setState(() => scanned = n);
    });
    if (!mounted) return;
    if (found != null) {
      await _save(found);
      _open();
    } else {
      setState(() {
        stage = Stage.setup;
        message = "Couldn't find the PC. Is run_faultline.bat running, "
            'and is the phone on the same Wi-Fi?';
      });
    }
  }

  Future<void> _save(String h) async {
    host = h;
    field.text = h;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('host', h);
  }

  void _open() {
    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(kBg)
      ..setNavigationDelegate(NavigationDelegate(
        onWebResourceError: (err) {
          if (err.isForMainFrame ?? true) _lost();
        },
      ))
      ..loadRequest(Uri.parse('http://$host/'));
    WakelockPlus.enable();
    setState(() {
      web = c;
      stage = Stage.connected;
    });
    _watch();
  }

  // The tablet page keeps polling the PC itself; this just notices when the
  // PC goes away (game closed, PC off) so we can show a clear message.
  Future<void> _watch() async {
    int misses = 0;
    while (mounted && stage == Stage.connected) {
      await Future.delayed(const Duration(seconds: 5));
      if (!mounted || stage != Stage.connected) return;
      if (await probe(host) == null) {
        misses++;
        if (misses >= 3) _lost();
      } else {
        misses = 0;
      }
    }
  }

  void _lost() {
    if (!mounted || stage == Stage.lost) return;
    WakelockPlus.disable();
    setState(() {
      stage = Stage.lost;
      message = 'Lost connection to the PC at $host.';
    });
  }

  @override
  Widget build(BuildContext context) {
    if (stage == Stage.connected && web != null) {
      return Scaffold(
        backgroundColor: kBg,
        body: SafeArea(child: WebViewWidget(controller: web!)),
      );
    }
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.build_circle, size: 72, color: kAmber),
                  const SizedBox(height: 8),
                  const Text('FaultLine',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 24),
                  Text(message, textAlign: TextAlign.center),
                  const SizedBox(height: 20),
                  ..._body(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _body() {
    switch (stage) {
      case Stage.checking:
        return [const Center(child: CircularProgressIndicator())];
      case Stage.scanning:
        return [
          LinearProgressIndicator(value: scanned / 254),
          const SizedBox(height: 8),
          Text('$scanned / 254', textAlign: TextAlign.center),
        ];
      case Stage.lost:
      case Stage.setup:
      case Stage.connected:
        return [
          FilledButton.icon(
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
            onPressed: () => _connect(),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            icon: const Icon(Icons.wifi_find),
            label: const Text('Search Wi-Fi for the PC'),
            onPressed: _scan,
          ),
          const SizedBox(height: 28),
          const Text('Or type the "On phone" address the PC shows:'),
          const SizedBox(height: 8),
          TextField(
            controller: field,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: '192.168.0.143:8080',
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.tonal(
            child: const Text('Connect'),
            onPressed: () async {
              var h = field.text.trim();
              h = h.replaceFirst(RegExp(r'^https?://'), '');
              h = h.replaceAll(RegExp(r'/+$'), '');
              if (h.isEmpty) return;
              if (!h.contains(':')) h = '$h:$kDefaultPort';
              await _save(h);
              await _connect();
            },
          ),
          const SizedBox(height: 24),
          const Text(
            'The PC has to be on with run_faultline.bat running. '
            'If the phone still can\'t connect, allow Python through '
            'Windows Firewall on private networks.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.white60),
          ),
        ];
    }
  }
}

/// Returns [host] if a FaultLine tablet answers there, else null.
Future<String?> probe(String host) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(milliseconds: 800);
  try {
    final req = await client
        .getUrl(Uri.parse('http://$host/'))
        .timeout(const Duration(seconds: 1));
    final resp = await req.close().timeout(const Duration(seconds: 2));
    if (resp.statusCode != 200) return null;
    final body = await resp
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 3));
    return body.contains('FaultLine') ? host : null;
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}

/// Scans the phone's own Wi-Fi subnet(s) for the FaultLine PC.
Future<String?> findPc(int port, void Function(int) progress) async {
  final prefixes = <String>{};
  try {
    final ifaces =
        await NetworkInterface.list(type: InternetAddressType.IPv4);
    for (final i in ifaces) {
      for (final a in i.addresses) {
        if (a.isLoopback) continue;
        final p = a.address.split('.');
        if (p.length == 4) prefixes.add('${p[0]}.${p[1]}.${p[2]}');
      }
    }
  } catch (_) {}
  if (prefixes.isEmpty) prefixes.add('192.168.0');

  for (final pre in prefixes) {
    for (int start = 1; start < 255; start += 32) {
      final jobs = <Future<String?>>[];
      for (int h = start; h < start + 32 && h < 255; h++) {
        jobs.add(probe('$pre.$h:$port'));
      }
      final results = await Future.wait(jobs);
      progress(start + 31 > 254 ? 254 : start + 31);
      for (final r in results) {
        if (r != null) return r;
      }
    }
  }
  return null;
}
