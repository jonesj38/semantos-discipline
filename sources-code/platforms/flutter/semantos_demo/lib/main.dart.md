---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/flutter/semantos_demo/lib/main.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.027376+00:00
---

# platforms/flutter/semantos_demo/lib/main.dart

```dart
import 'dart:convert' show utf8;
import 'dart:typed_data' show Uint8List;

import 'package:flutter/material.dart';
import 'package:semantos_ffi/semantos_ffi.dart';

void main() {
  runApp(const SemantosDemo());
}

class SemantosDemo extends StatelessWidget {
  const SemantosDemo({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Semantos Demo',
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
      ),
      home: const DemoPage(),
    );
  }
}

class DemoPage extends StatefulWidget {
  const DemoPage({super.key});

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  late SemantosKernel _kernel;
  String _status = 'Not initialized';
  String _cellData = '';
  String _version = '';
  final List<String> _log = [];
  final _pathController = TextEditingController(text: '/demo/cell');
  final _dataController = TextEditingController(text: 'Hello, Semantos!');

  @override
  void initState() {
    super.initState();
    _kernel = SemantosKernel();
  }

  void _addLog(String message) {
    setState(() {
      _log.insert(
          0,
          '${DateTime.now().toIso8601String().substring(11, 19)} $message');
      if (_log.length > 50) _log.removeLast();
    });
  }

  Future<void> _initialize() async {
    try {
      await _kernel.initialize('{}');
      final ver = _kernel.version();
      setState(() {
        _status = 'Initialized';
        _version = ver;
      });
      _addLog('Kernel initialized (version: $ver)');
    } on SemantosException catch (e) {
      setState(() => _status = 'Init failed');
      _addLog('Init error: $e');
    }
  }

  Future<void> _shutdown() async {
    try {
      await _kernel.shutdown();
      setState(() {
        _status = 'Shut down';
        _cellData = '';
      });
      _addLog('Kernel shut down');
    } on SemantosException catch (e) {
      _addLog('Shutdown error: $e');
    }
  }

  Future<void> _writeCell() async {
    final path = _pathController.text;
    final text = _dataController.text;
    final data = Uint8List.fromList(utf8.encode(text));
    try {
      await _kernel.cellWrite(path, data);
      setState(() => _status = 'Cell written');
      _addLog('Wrote ${data.length} bytes to $path');
    } on SemantosException catch (e) {
      _addLog('Write error: $e');
    }
  }

  Future<void> _readCell() async {
    final path = _pathController.text;
    try {
      final data = await _kernel.cellRead(path);
      if (data == null) {
        setState(() {
          _cellData = '(not found)';
          _status = 'Cell not found';
        });
        _addLog('Read $path: not found');
      } else {
        final text = utf8.decode(data);
        setState(() {
          _cellData = text;
          _status = 'Cell read: ${data.length} bytes';
        });
        _addLog('Read ${data.length} bytes from $path: $text');
      }
    } on SemantosException catch (e) {
      _addLog('Read error: $e');
    }
  }

  Future<void> _verifyCell() async {
    final path = _pathController.text;
    try {
      final data = await _kernel.cellRead(path);
      if (data == null) {
        _addLog('Verify: cell not found at $path');
        return;
      }
      // For demo: construct a 32-byte proof from the data.
      // The kernel expects SHA-256 in the first 32 bytes.
      final proof = Uint8List(32);
      for (var i = 0; i < data.length && i < 32; i++) {
        proof[i] = data[i];
      }
      final valid = await _kernel.cellVerify(path, proof);
      setState(() => _status = valid ? 'Proof valid' : 'Proof invalid');
      _addLog('Verify $path: ${valid ? "VALID" : "INVALID"}');
    } on SemantosException catch (e) {
      _addLog('Verify error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Semantos Demo'),
        actions: [
          if (_version.isNotEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text('v$_version',
                    style: Theme.of(context).textTheme.bodySmall),
              ),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status bar
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(
                      _kernel.isInitialized
                          ? Icons.check_circle
                          : Icons.cancel,
                      color:
                          _kernel.isInitialized ? Colors.green : Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_status)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Lifecycle buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _kernel.isInitialized ? null : _initialize,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Initialize'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _kernel.isInitialized ? _shutdown : null,
                    icon: const Icon(Icons.stop),
                    label: const Text('Shutdown'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Path and data inputs
            TextField(
              controller: _pathController,
              decoration: const InputDecoration(
                labelText: 'Cell Path',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.folder),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _dataController,
              decoration: const InputDecoration(
                labelText: 'Cell Data',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.data_object),
              ),
            ),
            const SizedBox(height: 8),

            // Operation buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _kernel.isInitialized ? _writeCell : null,
                    icon: const Icon(Icons.save),
                    label: const Text('Write'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _kernel.isInitialized ? _readCell : null,
                    icon: const Icon(Icons.download),
                    label: const Text('Read'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _kernel.isInitialized ? _verifyCell : null,
                    icon: const Icon(Icons.verified),
                    label: const Text('Verify'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Read result
            if (_cellData.isNotEmpty)
              Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Cell Data',
                          style: Theme.of(context).textTheme.labelMedium),
                      const SizedBox(height: 4),
                      Text(
                        _cellData,
                        style: Theme.of(context)
                            .textTheme
                            .bodyLarge
                            ?.copyWith(fontFamily: 'monospace'),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),

            // Event log
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Event Log',
                          style: Theme.of(context).textTheme.labelMedium),
                      const Divider(),
                      Expanded(
                        child: ListView.builder(
                          itemCount: _log.length,
                          itemBuilder: (context, index) => Text(
                            _log[index],
                            style: const TextStyle(
                                fontFamily: 'monospace', fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pathController.dispose();
    _dataController.dispose();
    super.dispose();
  }
}

```
