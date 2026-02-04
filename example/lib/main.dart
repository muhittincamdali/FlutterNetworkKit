import 'package:flutter/material.dart';

void main() {
  runApp(const NetworkKitExampleApp());
}

/// Example app demonstrating FlutterNetworkKit features.
class NetworkKitExampleApp extends StatelessWidget {
  const NetworkKitExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FlutterNetworkKit Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const ApiExampleScreen(),
    );
  }
}

/// Screen demonstrating API calls with FlutterNetworkKit.
class ApiExampleScreen extends StatefulWidget {
  const ApiExampleScreen({super.key});

  @override
  State<ApiExampleScreen> createState() => _ApiExampleScreenState();
}

class _ApiExampleScreenState extends State<ApiExampleScreen> {
  bool _isLoading = false;
  String _response = 'Press the button to make an API call';

  Future<void> _makeApiCall() async {
    setState(() {
      _isLoading = true;
      _response = 'Loading...';
    });

    // Simulate API call
    await Future.delayed(const Duration(seconds: 2));

    setState(() {
      _isLoading = false;
      _response = '''
{
  "status": "success",
  "message": "API call completed successfully",
  "data": {
    "id": 1,
    "name": "FlutterNetworkKit Demo",
    "features": [
      "Interceptors",
      "Caching",
      "Code Generation",
      "Error Handling"
    ]
  }
}''';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('NetworkKit Example'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _makeApiCall,
              icon: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_download),
              label: Text(_isLoading ? 'Loading...' : 'Make API Call'),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    _response,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
