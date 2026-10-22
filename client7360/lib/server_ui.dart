import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class ServerTestingPage extends StatefulWidget {
  const ServerTestingPage({super.key});

  @override
  State<ServerTestingPage> createState() => _ServerTestingPageState();
}

class _ServerTestingPageState extends State<ServerTestingPage> {
  int _counter = 0;

  final TextEditingController _getValueController = TextEditingController();
  final TextEditingController _lastPostController = TextEditingController();
  final TextEditingController _getInfoController = TextEditingController();
  final TextEditingController _postInfoController = TextEditingController();
  final TextEditingController _postValueController = TextEditingController(
    text: 'bonjouj',
  );
  final TextEditingController _serverUrlController = TextEditingController(
    text: 'http://127.0.0.1:8000/data',
  );

  void _incrementCounter() {
    setState(() {
      // This call to setState tells the Flutter framework that something has
      // changed in this State, which causes it to rerun the build method below
      // so that the display can reflect the updated values. If we changed
      // _counter without calling setState(), then the build method would not be
      // called again, and so nothing would appear to happen.
      _counter++;
    });
  }

  Future<void> _fetchValue() async {
    final url = _serverUrlController.text.trim();
    try {
      final response = await http.get(Uri.parse(url));
      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _getValueController.text = (data['value'] ?? '').toString();
        _getInfoController.text = 'response(success): ${response.statusCode}';
      } else {
        _getInfoController.text = 'response(error): ${response.statusCode}';
      }
    } catch (e) {
      if (!mounted) return;
      _getInfoController.text = 'error';
    }
  }

  Future<void> _postValue() async {
    final url = _serverUrlController.text.trim();
    final value = _postValueController.text;

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'value': value}),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final postedValue = (data['value'] ?? '').toString();

        _lastPostController.text = postedValue;
        // _getValueController.text = postedValue;
        _postInfoController.text = 'response(success): ${response.statusCode}';
      } else {
        _postInfoController.text = 'response(error): ${response.statusCode}';
      }
    } catch (e) {
      if (!mounted) return;
      _postInfoController.text = 'error';
    }
  }

  @override
  void dispose() {
    _getValueController.dispose();
    _lastPostController.dispose();
    _postValueController.dispose();
    _serverUrlController.dispose();
    _postInfoController.dispose();
    _getInfoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
        // TRY THIS: Try changing the color here to a specific color (to
        // Colors.amber, perhaps?) and trigger a hot reload to see the AppBar
        // change color while the other colors stay the same.
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        // title: Text(widget.title),
        title: const Text('Server UI'),
        leading: BackButton(
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        child: Center(
          // Center is a layout widget. It takes a single child and positions it
          // in the middle of the parent.
          child: Column(
            // Column is also a layout widget. It takes a list of children and
            // arranges them vertically. By default, it sizes itself to fit its
            // children horizontally, and tries to be as tall as its parent.
            //
            // Column has various properties to control how it sizes itself and
            // how it positions its children. Here we use mainAxisAlignment to
            // center the children vertically; the main axis here is the vertical
            // axis because Columns are vertical (the cross axis would be
            // horizontal).
            //
            // TRY THIS: Invoke "debug painting" (choose the "Toggle Debug Paint"
            // action in the IDE, or press "p" in the console), to see the
            // wireframe for each widget.
            mainAxisAlignment: .center,
            children: [
              const Text('You have pushed the button this many times:'),
              Text(
                '$_counter',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 20),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: TextField(
                  controller: _serverUrlController,
                  decoration: const InputDecoration(
                    labelText: 'server URL',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),

              const SizedBox(height: 48),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: TextField(
                  controller: _getValueController,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'GET value',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: TextField(
                  controller: _lastPostController,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'last POSTed value',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),

              const SizedBox(height: 48),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: TextField(
                  controller: _postValueController,
                  decoration: const InputDecoration(
                    labelText: 'value for POST',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),

              const SizedBox(height: 48),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: TextField(
                  controller: _getInfoController,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'GET response info',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: TextField(
                  controller: _postInfoController,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'POST response info',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: _fetchValue,
                    child: const Text('GET'),
                  ),
                  const SizedBox(width: 32),
                  ElevatedButton(
                    onPressed: _postValue,
                    child: const Text('POST'),
                  ),
                ],
              ),

              const SizedBox(height: 16),

            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ),
    );
  }
}
