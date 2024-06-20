import 'package:audio_service/audio_service.dart';
import 'package:example/core/core_audio_player.dart';
import 'package:just_audio/just_audio.dart';

class CoreAudioPlayerHandler extends BaseAudioHandler with SeekHandler {
  late final CoreAudioPlayer player;

  CoreAudioPlayerHandler() {
    player = CoreAudioPlayer();
    player.playbackEventStream.map(_transformEvent).pipe(playbackState);
    player.durationStream.listen((duration) {
      mediaItem.add(MediaItem(
        id: "audio-1",
        title: "Ocean Breeze Beat",
        album: "Pixabay Samples",
        artist: "JTWAYNE",
        artUri: Uri.parse("https://cdn.pixabay.com/audio/2024/05/29/21-39-37-801_200x200.jpg"),
        duration: duration
      ));
    });
  }

  @override
  Future<void> play() => player.play();

  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> seek(Duration position) => player.seek(position);

  @override
  Future<void> stop() => player.stop();

  PlaybackState _transformEvent(PlaybackEvent event) {
    return PlaybackState(
      controls: [
        MediaControl.rewind,
        if (player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.stop,
        MediaControl.fastForward,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 3],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[player.processingState]!,
      playing: player.playing,
      updatePosition: player.position,
      bufferedPosition: player.bufferedPosition,
      speed: player.speed,
      queueIndex: event.currentIndex,
    );
  }
}
