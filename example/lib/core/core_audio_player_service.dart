import 'package:audio_service/audio_service.dart';
import 'package:example/core/core_audio_player_handler.dart';

class CoreAudioService {
  CoreAudioService._();

  static final CoreAudioService _instance = CoreAudioService._();
  static CoreAudioService get instance => _instance;

  static CoreAudioPlayerHandler get audioHandler => _instance._audioHandler;

  late CoreAudioPlayerHandler _audioHandler;

  Future<void> initialize() async {
    _audioHandler = await AudioService.init(
      builder: () => CoreAudioPlayerHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.encrypted.example.channel.audio',
        androidNotificationChannelName: 'Encrypted audio playback',
        androidNotificationOngoing: true,
      ),
    );
  }
}