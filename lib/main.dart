import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Call Recorder',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const CallLogScreen(),
    );
  }
}

class CallLogScreen extends StatefulWidget {
  const CallLogScreen({super.key});

  @override
  State<CallLogScreen> createState() => _CallLogScreenState();
}

class _CallLogScreenState extends State<CallLogScreen>
    with WidgetsBindingObserver {
  static const MethodChannel _ch = MethodChannel('call_recorder');

  bool _loading = true;
  bool _hasPermissions = false;
  bool _batteryOk = true;
  List<Map<String, dynamic>> _calls = [];
  String? _playingPath;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'playbackDone' && mounted) {
        setState(() => _playingPath = null);
      }
    });
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    try {
      final perm = await _ch.invokeMethod<bool>('hasPermissions') ?? false;
      final battery = await _ch.invokeMethod<bool>('batteryOk') ?? true;
      final raw = await _ch.invokeMethod<List<dynamic>>('getCalls') ?? [];
      if (!mounted) return;
      setState(() {
        _hasPermissions = perm;
        _batteryOk = battery;
        _calls = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _requestPermissions() async {
    await _ch.invokeMethod('requestPermissions');
    await _load();
  }

  Future<void> _requestBattery() async {
    await _ch.invokeMethod('requestBatteryExemption');
  }

  Future<void> _togglePlay(String path) async {
    if (_playingPath == path) {
      await _ch.invokeMethod('stop');
      if (mounted) setState(() => _playingPath = null);
      return;
    }
    try {
      await _ch.invokeMethod('play', {'path': path});
      if (mounted) setState(() => _playingPath = path);
    } on PlatformException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cannot play recording: ${e.message}')),
      );
    }
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  String _formatTime(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final ampm = d.hour >= 12 ? 'PM' : 'AM';
    return '${_two(d.day)}/${_two(d.month)}/${d.year}  $h:${_two(d.minute)} $ampm';
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m}m ${_two(s)}s';
  }

  Widget _banner(String title, String subtitle, String button, VoidCallback onTap) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(subtitle),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: onTap, child: Text(button)),
          ],
        ),
      ),
    );
  }

  Widget _callTile(Map<String, dynamic> call) {
    final number = (call['number'] as String?) ?? 'Unknown';
    final name = call['name'] as String?;
    final incoming = call['direction'] == 'incoming';
    final duration = (call['duration'] as num?)?.toInt() ?? 0;
    final start = (call['startTime'] as num?)?.toInt() ?? 0;
    final recording = call['recording'] as String?;
    final playing = recording != null && recording == _playingPath;

    return ListTile(
      leading: Icon(
        incoming ? Icons.call_received : Icons.call_made,
        color: incoming ? Colors.green : Colors.blue,
      ),
      title: Text(
        (name != null && name.isNotEmpty) ? '$name  ($number)' : number,
      ),
      subtitle: Text(
        '${_formatTime(start)}\n'
        'Duration: ${_formatDuration(duration)}',
      ),
      isThreeLine: true,
      trailing: recording == null
          ? const Text('No recording', style: TextStyle(fontSize: 12))
          : IconButton(
              icon: Icon(playing ? Icons.stop_circle : Icons.play_circle),
              iconSize: 36,
              onPressed: () => _togglePlay(recording),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Call Recorder')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (!_hasPermissions)
                  _banner(
                    'Permissions needed',
                    'Allow phone, call log and microphone access so calls can be saved.',
                    'Grant permissions',
                    _requestPermissions,
                  ),
                if (_hasPermissions && !_batteryOk)
                  _banner(
                    'Allow background running',
                    'Without this, Android may block recording when the app is closed.',
                    'Allow',
                    _requestBattery,
                  ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _load,
                    child: _calls.isEmpty
                        ? ListView(
                            children: const [
                              SizedBox(height: 120),
                              Center(child: Text('No calls saved yet')),
                            ],
                          )
                        : ListView.separated(
                            itemCount: _calls.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (_, i) => _callTile(_calls[i]),
                          ),
                  ),
                ),
              ],
            ),
    );
  }
}
