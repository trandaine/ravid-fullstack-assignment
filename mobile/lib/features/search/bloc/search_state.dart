import 'package:equatable/equatable.dart';
import '../data/models/search_result.dart';

abstract class SearchState extends Equatable {
  final String query;
  final double threshold;
  final int topK;

  const SearchState({
    this.query = '',
    this.threshold = 0.5,
    this.topK = 5,
  });

  @override
  List<Object?> get props => [query, threshold, topK];
}

class SearchInitial extends SearchState {
  const SearchInitial({super.query, super.threshold, super.topK});
}

class SearchLoading extends SearchState {
  const SearchLoading({super.query, super.threshold, super.topK});
}

class SearchLoaded extends SearchState {
  final List<SourceChunk> results;
  final bool isEmpty;

  const SearchLoaded({
    required this.results,
    required this.isEmpty,
    super.query,
    super.threshold,
    super.topK,
  });

  @override
  List<Object?> get props => [results, isEmpty, query, threshold, topK];
}

class SearchFailure extends SearchState {
  final String error;

  const SearchFailure({
    required this.error,
    super.query,
    super.threshold,
    super.topK,
  });

  @override
  List<Object?> get props => [error, query, threshold, topK];
}
