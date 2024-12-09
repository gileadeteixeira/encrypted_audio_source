import 'package:encrypted_audio_source/custom_audio_source.dart';
import 'package:encrypted_audio_source/encrypted_audio_source.dart';
import 'package:example/core/core_audio_player_service.dart';
import 'package:example/core/core_encrypter.dart';
import 'package:example/ui/main_screen.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';

void main() async {
  await CoreAudioService.instance.initialize();

  const url = "https://github.com/gileadeteixeira/samples/raw/refs/heads/develop/encrypted_example.mp3.aes";
  // const url = "https://dovetail.prxu.org/70/66673fd4-6851-4b90-a762-7c0538c76626/CoryCombs_2021T_VO_Intro.mp3";

  // final myCustomSource = EncryptedAudioSource(
  //   generator: generator,
  //   decrypter: CoreEncrypter.decrypt,
  // );

  final myCustomSource = CustomAudioSource(
    Uri.parse(url),
    fileExtension: ".mp3",
    customDecrypterGenerator: () {
      final teste = TesteEncrypter();
      return CustomDecrypter(
        decrypter: teste.decrypt,
        resetter: teste.decrypter.reset
      );
    },
  );

  // await myCustomSource.clearCache();
  // await Future.delayed(const Duration(seconds: 3));
  // return;

  final player = CoreAudioService.audioHandler.player;
  // final player = AudioPlayer();

  await player.setAudioSource(
    myCustomSource,
    // customDurationStream: myCustomSource.totalDurationStream
  );

  Future.delayed(
    const Duration(milliseconds: 500),
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
