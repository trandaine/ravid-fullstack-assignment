import 'package:equatable/equatable.dart';

abstract class SearchEvent extends Equatable {
  const SearchEvent();

  @override
  List<Object?> get props => [];
}

class SearchQueryChanged extends SearchEvent {
  final String query;

  const SearchQueryChanged({required this.query});

  @override
  List<Object?> get props => [query];
}

class ThresholdChanged extends SearchEvent {
  final double threshold;

  const ThresholdChanged({required this.threshold});

  @override
  List<Object?> get props => [threshold];
}

class TopKChanged extends SearchEvent {
  final int topK;

  const TopKChanged({required this.topK});

  @override
  List<Object?> get props => [topK];
}

class SearchCleared extends SearchEvent {
  const SearchCleared();
}
