import 'dart:async';

StreamController<void> createUnauthenticatedStreamController() =>
    StreamController<void>.broadcast();

final unauthenticatedEventStream = StreamController<void>.broadcast();

