import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Call Recordings',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const RecordingsScreen(),
    );
  }
}

class Recording {
  final String name;
  final String path;
  final String folder;
  final int size;
  final DateTime date;

  const Recording({
    required this.name,
    required this.path,
    required this.folder,
    required this.size,
    required this.date,
  });
}

class RecordingsScreen extends StatefulWidget {
  const RecordingsScreen({super.key});

  @override
  State<RecordingsScreen> createState() => _RecordingsScreenState();
}

class _RecordingsScreenState extends State<RecordingsScreen>
    with WidgetsBindingObserver {
  static const MethodChannel _ch = MethodChannel('storage_access');
  static const Set<String> _audioExt = {
    'm4a', 'mp3', 'amr', 'aac', 'wav', '3gp', 'ogg', 'opus', 'awb', 'flac',
  };

  int _sdk = 0;
  bool _hasAccess = false;
  bool _scanning = false; // full scan running
  bool _busy = false; // any scan running
  bool _firstScanDone = false;

  List<Recording> _recordings = [];
  final Set<String> _baseline = {}; // recordings that existed at first scan
  final Set<String> _newPaths = {}; // recordings which appeared afterwards
  final Set<String> _knownFolders = {};
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _quickScan());
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _onResume();
  }

  Future<void> _init() async {
    try {
      _sdk = await _ch.invokeMethod<int>('sdk') ?? 0;
    } catch (_) {}
    await _checkAccess();
    if (_hasAccess) await _discover();
  }

  Future<void> _onResume() async {
    await _checkAccess();
    if (!_hasAccess) return;
    if (!_firstScanDone) {
      await _discover();
    } else {
      await _quickScan();
    }
  }

  Future<void> _checkAccess() async {
    bool ok = false;
    try {
      ok = await _ch.invokeMethod<bool>('hasAccess') ?? false;
    } catch (_) {}
    if (mounted) setState(() => _hasAccess = ok);
  }

  Future<void> _requestAccess() async {
    try {
      await _ch.invokeMethod('requestAccess');
    } catch (_) {}
  }

  // ---------------- scanning ----------------

  /// Full scan: walks the whole internal storage looking for audio files whose
  /// path contains "call" or "rec". Also tells us WHERE recordings are kept.
  Future<void> _discover() async {
    if (_busy) return;
    _busy = true;
    if (mounted) setState(() => _scanning = true);

    final found = <Recording>[];
    try {
      Directory root = Directory('/storage/emulated/0');
      if (!await root.exists()) root = Directory('/sdcard');
      await _walk(root, 0, found);
    } catch (_) {}

    _knownFolders
      ..clear()
      ..addAll(found.map((r) => r.folder));
    _apply(found);
    _busy = false;
    if (mounted) setState(() => _scanning = false);
  }

  /// Quick scan: only re-lists the folders where recordings were already found.
  /// Runs every 5 seconds while the app is open.
  Future<void> _quickScan() async {
    if (!mounted || _busy || !_hasAccess || !_firstScanDone) return;
    if (_knownFolders.isEmpty) return;
    _busy = true;

    final found = <Recording>[];
    for (final folder in _knownFolders.toList()) {
      try {
        final items = await Directory(folder).list(followLinks: false).toList();
        for (final e in items) {
          if (e is File) {
            final rec = await _toRecording(e, requireHint: false);
            if (rec != null) found.add(rec);
          }
        }
      } catch (_) {}
    }
    _apply(found);
    _busy = false;
  }

  Future<void> _walk(Directory dir, int depth, List<Recording> out) async {
    if (depth > 8) return;
    List<FileSystemEntity> items;
    try {
      items = await dir.list(followLinks: false).toList();
    } catch (_) {
      return; // folder not readable
    }
    for (final e in items) {
      final name = e.path.split('/').last;
      if (e is Directory) {
        if (name == 'Android' || name.startsWith('.')) continue;
        await _walk(e, depth + 1, out);
      } else if (e is File) {
        final rec = await _toRecording(e, requireHint: true);
        if (rec != null) out.add(rec);
      }
    }
  }

  Future<Recording?> _toRecording(File f, {required bool requireHint}) async {
    final path = f.path;
    final name = path.split('/').last;
    final dot = name.lastIndexOf('.');
    if (dot < 0) return null;
    final ext = name.substring(dot + 1).toLowerCase();
    if (!_audioExt.contains(ext)) return null;
    if (requireHint) {
      final lower = path.toLowerCase();
      if (!lower.contains('call') && !lower.contains('rec')) return null;
    }
    try {
      final stat = await f.stat();
      return Recording(
        name: name,
        path: path,
        folder: path.substring(0, path.length - name.length - 1),
        size: stat.size,
        date: stat.modified,
      );
    } catch (_) {
      return null;
    }
  }

  void _apply(List<Recording> found) {
    if (!mounted) return;
    found.sort((a, b) => b.date.compareTo(a.date));

    if (!_firstScanDone) {
      _baseline.addAll(found.map((r) => r.path));
      _firstScanDone = true;
    } else {
      final fresh = found
          .where((r) =>
              !_baseline.contains(r.path) && !_newPaths.contains(r.path))
          .toList();
      if (fresh.isNotEmpty) {
        _newPaths.addAll(fresh.map((r) => r.path));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('New recording found: ${fresh.first.name}')),
        );
      }
    }
    setState(() => _recordings = found);
  }

  // ---------------- formatting ----------------

  String _two(int n) => n.toString().padLeft(2, '0');

  String _formatTime(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final ampm = d.hour >= 12 ? 'PM' : 'AM';
    return '${_two(d.day)}/${_two(d.month)}/${d.year}  $h:${_two(d.minute)} $ampm';
  }

  String _formatSize(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Call Recordings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Scan again',
            onPressed: _hasAccess ? _discover : null,
          ),
        ],
        bottom: _scanning
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(),
              )
            : null,
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_sdk != 0 && _sdk < 30) {
      return _message('This test build needs Android 11 or newer.', null, null);
    }
    if (!_hasAccess) {
      return _message(
        'To find call recordings, the app needs "All files access". '
        'A settings screen will open: switch it on for this app, then come back.',
        'Allow file access',
        _requestAccess,
      );
    }
    if (!_firstScanDone) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Scanning for recordings...'),
          ],
        ),
      );
    }
    return Column(
      children: [
        _summary(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _discover,
            child: _recordings.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 100),
                      Center(child: Text('No recordings found yet')),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: _recordings.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) => _tile(_recordings[i]),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _message(String text, String? button, VoidCallback? onTap) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, textAlign: TextAlign.center),
            if (button != null) ...[
              const SizedBox(height: 16),
              ElevatedButton(onPressed: onTap, child: Text(button)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _summary() {
    final byFolder = <String, int>{};
    for (final r in _recordings) {
      byFolder[r.folder] = (byFolder[r.folder] ?? 0) + 1;
    }
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _recordings.isEmpty
                  ? 'No recordings found yet. Make a call with your phone\'s '
                      'call recorder on, then tap the refresh button.'
                  : 'Found ${_recordings.length} recording(s) in '
                      '${byFolder.length} folder(s):',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            for (final e in byFolder.entries)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: SelectableText('${e.key}  (${e.value})'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _tile(Recording r) {
    final isNew = _newPaths.contains(r.path);
    return ListTile(
      leading: const Icon(Icons.phone_in_talk),
      title: Text(r.name),
      subtitle: Text('${_formatTime(r.date)}  •  ${_formatSize(r.size)}'),
      trailing: isNew
          ? const Chip(label: Text('NEW'), visualDensity: VisualDensity.compact)
          : null,
    );
  }
}