import 'package:encrypted_audio_source/encrypted_audio_source.dart';
import 'package:example/core/core_audio_player_service.dart';
import 'package:example/core/core_encrypter.dart';
import 'package:example/ui/main_screen.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() async {
  await CoreAudioService.instance.initialize();

  const url = "https://github.com/App2Sales/samples/raw/main/encrypted_example.mp3.aes";

  final uri = Uri.parse(url);
  final request = http.Request('GET', uri);
  final response = await request.send();
  final stream = response.stream;

  final myCustomSource = EncryptedAudioSource(
    encryptedStream: stream,
    decrypter: CoreEncrypter.decrypt,
    sourceLength: response.contentLength
  );

  final player = CoreAudioService.audioHandler.player;

  await player.setAudioSource(myCustomSource);

  Future.delayed(
    const Duration(seconds: 3),
    player.play
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Encrypted Audio Source Demo',
      theme: ThemeData(primarySwatch: Colors.deepPurple),
      home: const MainScreen(),
    );
  }
}
