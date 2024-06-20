import 'package:just_audio/just_audio.dart';

class CoreAudioPlayer extends AudioPlayer {
  CoreAudioPlayer({
    super.userAgent,
    super.handleInterruptions = true,
    super.androidApplyAudioAttributes = true,
    super.handleAudioSessionActivation = true,
    super.audioLoadConfiguration,
    super.audioPipeline,
    super.androidOffloadSchedulingEnabled = false,
    super.useProxyForRequestHeaders = true,
  });

  Stream<Duration>? _customDurationStream;
  @override
  Stream<Duration?> get durationStream => _customDurationStream ?? super.durationStream;

  Duration? _customDuration;
  @override
  Duration? get duration => _customDuration ?? super.duration;

  @override
  Future<Duration?> setAudioSource(
    AudioSource source, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
    Stream<Duration>? customDurationStream,
    Duration? customDuration
  }) async {
    final future = super.setAudioSource(
      source,
      preload: preload,
      initialIndex: initialIndex,
      initialPosition: initialPosition
    );
    _customDuration = customDuration;
    _customDurationStream = customDurationStream;

    _customDurationStream?.listen((duration){
      _customDuration = duration;
    });

    if (customDuration != null) {
      await future;
      return customDuration;

    } else {
      return future;
    }
  }
}