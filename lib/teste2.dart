import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';

class CustomDecrypter {
  final List<int> Function(List<int> bytes) decrypter;
  final Function()? resetter;

  CustomDecrypter({
    required this.decrypter,
    this.resetter
  });
}

class _InProgressCacheResponse {
  // NOTE: This isn't necessarily memory efficient. Since the entire audio file
  // will likely be downloaded at a faster rate than the rate at which the
  // player is consuming audio data, it is also likely that this buffered data
  // will never be used.
  // TODO: Improve this code.
  // ignore: close_sinks
  final controller = ReplaySubject<List<int>>();
  final int? end;
  _InProgressCacheResponse({
    required this.end,
  });
}

class _StreamingByteRangeRequest {
  /// The start of the range request.
  final int? start;

  /// The end of the range request.
  final int? end;

  /// Completes when the response is available.
  final _completer = Completer<StreamAudioResponse>();

  _StreamingByteRangeRequest(this.start, this.end);

  /// The response for this request.
  Future<StreamAudioResponse> get future => _completer.future;

  /// Completes this request with the given [response].
  void complete(StreamAudioResponse response) {
    if (_completer.isCompleted) {
      return;
    }
    _completer.complete(response);
  }

  /// Fails this request with the given [error] and [stackTrace].
  void fail(dynamic error, [StackTrace? stackTrace]) {
    if (_completer.isCompleted) {
      return;
    }
    _completer.completeError(error as Object, stackTrace);
  }
}

class CustomAudioSource extends StreamAudioSource {
  Future<HttpClientResponse>? _response;
  final Uri uri;
  final Map<String, String>? headers;
  int _progress = 0;
  final _requests = <_StreamingByteRangeRequest>[];
  final _downloadProgressSubject = BehaviorSubject<double>();
  bool _downloading = false;
  String? userAgent;
  CustomDecrypter Function()? customDecrypterGenerator;

  /// Creates a [CustomAudioSource] to that provides [uri] to the player
  /// while simultaneously caching it to [cacheFile]. If no cache file is
  /// supplied, just_audio will allocate a cache file internally.
  ///
  /// If headers are set, just_audio will create a cleartext local HTTP proxy on
  /// your device to forward HTTP requests with headers included.
  CustomAudioSource(
    this.uri, {
    super.tag,
    this.headers,
    this.userAgent,
    this.customDecrypterGenerator,
  }) {
    _downloadProgressSubject.add(0.0);
  }

  /// Returns a [UriAudioSource] resolving directly to the cache file if it
  /// exists, otherwise returns `this`. This can be
  IndexedAudioSource resolve() => this;

  /// Emits the current download progress as a double value from 0.0 (nothing
  /// downloaded) to 1.0 (download complete).
  Stream<double> get downloadProgressStream => _downloadProgressSubject.stream;

  /// Removes the underlying cache files. It is an error to clear the cache
  /// while a download is in progress.
  void clearCache() {
    if (_downloading) {
      throw Exception("Cannot clear cache while download is in progress");
    }
    _progress = 0;
    _downloadProgressSubject.add(0.0);
  }

  /// Start downloading the whole audio file to the cache and fulfill byte-range
  /// requests during the download. There are 3 scenarios:
  ///
  /// 1. If the byte range request falls entirely within the cache region, it is
  /// fulfilled from the cache.
  /// 2. If the byte range request overlaps the cached region, the first part is
  /// fulfilled from the cache, and the region beyond the cache is fulfilled
  /// from a memory buffer of the downloaded data.
  /// 3. If the byte range request is entirely outside the cached region, a
  /// separate HTTP request is made to fulfill it while the download of the
  /// entire file continues in parallel.
  Future<HttpClientResponse> _fetch() async {
    _downloading = true;

    final httpClient = _createHttpClient(userAgent: userAgent);
    final httpRequest = await _getUrl(httpClient, uri, headers: headers);
    final response = await httpRequest.close();
    if (response.statusCode != 200) {
      httpClient.close();
      throw Exception('HTTP Status Error: ${response.statusCode}');
    }
    // TODO: Should close sink after done, but it throws an error.
    // ignore: close_sinks
    // IOSink sink
    final sourceLength =
        response.contentLength == -1 ? null : response.contentLength;
    final mimeType = response.headers.contentType.toString();
    final acceptRanges = response.headers.value(HttpHeaders.acceptRangesHeader);
    final originSupportsRangeRequests =
        acceptRanges != null && acceptRanges != 'none';
    final inProgressResponses = <_InProgressCacheResponse>[];
    late StreamSubscription<List<int>> subscription;
    var percentProgress = 0;
    void updateProgress(int newPercentProgress) {
      if (newPercentProgress != percentProgress) {
        percentProgress = newPercentProgress;
        _downloadProgressSubject.add(percentProgress / 100);
      }
    }

    _progress = 0;

    final masterDecrypter = customDecrypterGenerator?.call();

    subscription = response.listen((data) async {
      data = masterDecrypter?.decrypter.call(data) ?? data;

      _progress += data.length;
      final newPercentProgress = (sourceLength == null)
          ? 0
          : (sourceLength == 0)
              ? 100
              : (100 * _progress ~/ sourceLength);
      updateProgress(newPercentProgress);
      final readyRequests = _requests
          .where((request) =>
              !originSupportsRangeRequests ||
              request.start == null ||
              (request.start!) < _progress)
          .toList();
      final notReadyRequests = _requests
          .where((request) =>
              originSupportsRangeRequests &&
              request.start != null &&
              (request.start!) >= _progress)
          .toList();
      // Add this live data to any responses in progress.
      for (var cacheResponse in inProgressResponses) {
        final end = cacheResponse.end;
        if (end != null && _progress >= end) {
          // We've received enough data to fulfill the byte range request.
          final subEnd =
              min(data.length, max(0, data.length - (_progress - end)));
          cacheResponse.controller.add(data.sublist(0, subEnd));
          cacheResponse.controller.close();
        } else {
          cacheResponse.controller.add(data);
        }
      }
      inProgressResponses.removeWhere((element) => element.controller.isClosed);
      if (_requests.isEmpty) return;
      // Prevent further data coming from the HTTP source until we have set up
      // an entry in inProgressResponses to continue receiving live HTTP data.
      subscription.pause();
      // Process any requests that start within the cache.
      for (var request in readyRequests) {
        _requests.remove(request);
        int? start, end;
        if (originSupportsRangeRequests) {
          start = request.start;
          end = request.end;
        } else {
          // If the origin doesn't support range requests, the proxy should also
          // ignore range requests and instead serve a complete 200 response
          // which the client (AV or exo player) should know how to deal with.
        }
        final effectiveStart = start ?? 0;
        final effectiveEnd = end ?? sourceLength;
        Stream<List<int>> responseStream;
        final cacheResponse = _InProgressCacheResponse(end: effectiveEnd);
        inProgressResponses.add(cacheResponse);
        responseStream = Rx.concatEager([
          cacheResponse.controller.stream,
        ]);
        request.complete(StreamAudioResponse(
          rangeRequestsSupported: originSupportsRangeRequests,
          sourceLength: start != null ? sourceLength : null,
          contentLength:
              effectiveEnd != null ? effectiveEnd - effectiveStart : null,
          offset: start,
          contentType: mimeType,
          stream: responseStream.asBroadcastStream(),
        ));
      }
      subscription.resume();
      // Process any requests that start beyond the cache.
      for (var request in notReadyRequests) {
        _requests.remove(request);
        final start = request.start!;
        final end = request.end ?? sourceLength;
        final httpClient = _createHttpClient(userAgent: userAgent);
        final rangeRequest = _HttpRangeRequest(start, end);

        final innerDecrypter = customDecrypterGenerator?.call();

        _getUrl(httpClient, uri, headers: {
          if (headers != null) ...headers!,
          HttpHeaders.rangeHeader: rangeRequest.header,
        }).then((httpRequest) async {
          final response = await httpRequest.close();
          if (response.statusCode != 206) {
            httpClient.close();
            throw Exception('HTTP Status Error: ${response.statusCode}');
          }
          request.complete(StreamAudioResponse(
            rangeRequestsSupported: originSupportsRangeRequests,
            sourceLength: sourceLength,
            contentLength: end != null ? end - start : null,
            offset: start,
            contentType: mimeType,
            // stream: response.asBroadcastStream(),
            stream: response.map<List<int>>((bytes) {
              return innerDecrypter?.decrypter.call(bytes) ?? bytes;
            }).asBroadcastStream(),
          ));
        }, onError: (dynamic e, StackTrace? stackTrace) {
      print("oxe: ${[e, stackTrace]}");
          request.fail(e, stackTrace);
          innerDecrypter?.resetter?.call();
        }).onError((Object e, StackTrace st) {
          request.fail(e, st);
          innerDecrypter?.resetter?.call();
        });
      }
      
    }, onDone: () async {
      if (sourceLength == null) {
        updateProgress(100);
      }
      for (var cacheResponse in inProgressResponses) {
        if (!cacheResponse.controller.isClosed) {
          cacheResponse.controller.close();
        }
      }
      await subscription.cancel();
      httpClient.close();
      masterDecrypter?.resetter?.call();
      _downloading = false;

    }, onError: (Object e, StackTrace stackTrace) async {
      print("oxe: ${[e, stackTrace]}");
      httpClient.close();
      // Fail all pending requests
      for (final req in _requests) {
        req.fail(e, stackTrace);
      }
      _requests.clear();
      // Close all in progress requests
      for (final res in inProgressResponses) {
        res.controller.addError(e, stackTrace);
        res.controller.close();
      }
      masterDecrypter?.resetter?.call();
      _downloading = false;

    }, cancelOnError: true);

    return response;
  }

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {    
    final byteRangeRequest = _StreamingByteRangeRequest(start, end);
    _requests.add(byteRangeRequest);
    _response ??=
        _fetch().catchError((dynamic error, StackTrace? stackTrace) async {
      // So that we can restart later
      _response = null;
      // Cancel any pending request
      for (final req in _requests) {
        req.fail(error, stackTrace);
      }
      return Future<HttpClientResponse>.error(error as Object, stackTrace);
    });

    return byteRangeRequest.future.then((response) {
      response.stream.listen((event) {}, onError: (Object e, StackTrace st) {
        // So that we can restart later
        _response = null;
        // Cancel any pending request
        for (final req in _requests) {
          req.fail(e, st);
        }
      });
      return response;
    });
  }
}

class _HttpRangeRequest {
  /// The starting byte position of the range request.
  final int start;

  /// The last byte position of the range request, or `null` if requesting
  /// until the end of the media.
  final int? end;

  /// The end byte position (exclusive), defaulting to `null`.
  int? get endEx => end == null ? null : end! + 1;

  _HttpRangeRequest(this.start, this.end);

  /// Format a range header for this request.
  String get header =>
      'bytes=$start-${end != null ? (end! - 1).toString() : ""}';

  /// Creates an [_HttpRangeRequest] from [header].
  static _HttpRangeRequest? parse(List<String>? header) {
    if (header == null || header.isEmpty) return null;
    final match = RegExp(r'^bytes=(\d+)(-(\d+)?)?').firstMatch(header.first);
    if (match == null) return null;
    int? intGroup(int i) => match[i] != null ? int.parse(match[i]!) : null;
    return _HttpRangeRequest(intGroup(1)!, intGroup(3));
  }
}

Future<HttpClientRequest> _getUrl(HttpClient client, Uri uri,
    {Map<String, String>? headers}) async {
  final request = await client.getUrl(uri);
  if (headers != null) {
    final host = request.headers.value(HttpHeaders.hostHeader);
    request.headers.clear();
    request.headers.set(HttpHeaders.contentLengthHeader, '0');
    headers.forEach((name, value) => request.headers.set(name, value));
    if (host != null) {
      request.headers.set(HttpHeaders.hostHeader, host);
    }
    if (client.userAgent != null) {
      request.headers.set(HttpHeaders.userAgentHeader, client.userAgent!);
    }
  }
  // Match ExoPlayer's native behavior
  request.maxRedirects = 20;
  return request;
}

HttpClient _createHttpClient({String? userAgent}) {
  final client = HttpClient();
  if (userAgent != null) {
    client.userAgent = userAgent;
  }
  return client;
}