import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Request storage permission for Android (needed for file access)
  if (Platform.isAndroid) {
    await [
      Permission.storage,
      Permission.manageExternalStorage,
      Permission.accessMediaLocation,
    ].request();
  }
  runApp(const SwiftTransferApp());
}

class SwiftTransferApp extends StatelessWidget {
  const SwiftTransferApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Swift Transfer',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _status = "Ready. App is listening on port 12345.";
  final TextEditingController _ipController = TextEditingController();
  String _lastReceivedPath = "";

  // Receiver server socket
  ServerSocket? _serverSocket;

  @override
  void initState() {
    super.initState();
    _startReceiver();
  }

  @override
  void dispose() {
    _serverSocket?.close();
    _ipController.dispose();
    super.dispose();
  }

  // ---------- RECEIVER: listens on port 12345 ----------
  Future<void> _startReceiver() async {
    try {
      _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, 12345);
      setState(() {
        _status = "✅ Listening on port 12345\nSend files to this device's IP address";
      });
      _serverSocket!.listen((Socket socket) async {
        final dir = await getDownloadsDirectory();
        final receivePath = '${dir!.path}/received_${DateTime.now().millisecondsSinceEpoch}.bin';
        final file = File(receivePath);
        final sink = file.openWrite();
        int totalBytes = 0;
        setState(() {
          _status = "📥 Receiving file... (0 bytes)";
        });
        await socket.forEach((List<int> data) {
          sink.add(data);
          totalBytes += data.length;
          setState(() {
            _status = "📥 Receiving... ${(totalBytes / 1024).toStringAsFixed(1)} KB";
          });
        });
        await sink.close();
        setState(() {
          _status = "✅ File saved to Downloads:\n$receivePath";
          _lastReceivedPath = receivePath;
        });
        socket.close();
      });
    } catch (e) {
      setState(() => _status = "❌ Receiver error: $e");
    }
  }

  // ---------- SENDER: send file to given IP ----------
  Future<void> _sendFile(String ip, String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        setState(() => _status = "❌ File does not exist");
        return;
      }
      final size = await file.length();
      setState(() => _status = "🔌 Connecting to $ip:12345...");
      final socket = await Socket.connect(ip, 12345, timeout: const Duration(seconds: 5));
      setState(() => _status = "📤 Sending ${file.path.split('/').last} ($size bytes)");
      final stream = file.openRead();
      int sent = 0;
      await for (var chunk in stream) {
        socket.add(chunk);
        sent += chunk.length;
        final percent = (sent / size * 100).toStringAsFixed(1);
        setState(() {
          _status = "📤 Sending: $percent% (${(sent / 1024).toStringAsFixed(1)} KB / ${(size / 1024).toStringAsFixed(1)} KB)";
        });
      }
      await socket.flush();
      socket.close();
      setState(() => _status = "✅ Send complete!");
    } catch (e) {
      setState(() => _status = "❌ Send error: $e\nMake sure receiver is running on $ip");
    }
  }

  // Pick file and send
  Future<void> _pickAndSend() async {
    final result = await FilePicker.platform.pickFiles();
    if (result == null) return;
    final path = result.files.single.path!;
    final ip = _ipController.text.trim();
    if (ip.isEmpty) {
      setState(() => _status = "❌ Please enter receiver IP address");
      return;
    }
    await _sendFile(ip, path);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Swift Transfer"),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "How to use:",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            const Text(
              "1. On receiving device, open this app (it listens automatically).\n"
              "2. On sending device, enter receiver's local IP address.\n"
              "3. Pick a file and press Send.\n"
              "4. Received files are saved in Downloads folder.\n"
              "5. Works both ways: Android ↔ Windows, Android ↔ Android, etc.",
              style: TextStyle(fontSize: 13),
            ),
            const Divider(height: 30),
            TextField(
              controller: _ipController,
              decoration: const InputDecoration(
                labelText: "Receiver IP address (e.g., 192.168.1.100)",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.wifi),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _pickAndSend,
                    icon: const Icon(Icons.send),
                    label: const Text("Send File"),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final result = await FilePicker.platform.pickFiles();
                      if (result != null) {
                        final path = result.files.single.path!;
                        setState(() {
                          _status = "📁 Selected: ${result.files.single.name}";
                        });
                      }
                    },
                    icon: const Icon(Icons.folder_open),
                    label: const Text("Pick File"),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 30),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Status:",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(_status, style: const TextStyle(fontSize: 13)),
                  if (_lastReceivedPath.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      "Last received:\n$_lastReceivedPath",
                      style: const TextStyle(fontSize: 11, color: Colors.green),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
