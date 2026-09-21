import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../data/search_repository.dart';
import 'search_event.dart';
import 'search_state.dart';

class SearchBloc extends Bloc<SearchEvent, SearchState> {
  final SearchRepository _searchRepository;
  Timer? _debounceTimer;

  SearchBloc({required SearchRepository searchRepository})
      : _searchRepository = searchRepository,
        super(const SearchInitial()) {
    on<SearchQueryChanged>(_onSearchQueryChanged);
    on<ThresholdChanged>(_onThresholdChanged);
    on<TopKChanged>(_onTopKChanged);
    on<SearchCleared>(_onSearchCleared);
  }

  @override
  Future<void> close() {
    _debounceTimer?.cancel();
    return super.close();
  }

  Future<void> _onSearchQueryChanged(
    SearchQueryChanged event,
    Emitter<SearchState> emit,
  ) async {
    final newQuery = event.query;
    if (newQuery.trim().isEmpty) {
      _debounceTimer?.cancel();
      emit(SearchInitial(
        query: '',
        threshold: state.threshold,
        topK: state.topK,
      ));
      return;
    }

    emit(SearchLoading(
      query: newQuery,
      threshold: state.threshold,
      topK: state.topK,
    ));

    try {
      final response = await _searchRepository.search(
        query: newQuery.trim(),
        topK: state.topK,
        scoreThreshold: state.threshold,
      );

      emit(SearchLoaded(
        query: newQuery,
        threshold: state.threshold,
        topK: state.topK,
        results: response.results,
        isEmpty: response.results.isEmpty,
      ));
    } catch (e) {
      emit(SearchFailure(
        error: _parseError(e),
        query: newQuery,
        threshold: state.threshold,
        topK: state.topK,
      ));
    }
  }

  Future<void> _onThresholdChanged(
    ThresholdChanged event,
    Emitter<SearchState> emit,
  ) async {
    final newThreshold = event.threshold;
    if (state.query.trim().isEmpty) {
      emit(SearchInitial(
        query: state.query,
        threshold: newThreshold,
        topK: state.topK,
      ));
      return;
    }

    emit(SearchLoading(
      query: state.query,
      threshold: newThreshold,
      topK: state.topK,
    ));

    try {
      final response = await _searchRepository.search(
        query: state.query.trim(),
        topK: state.topK,
        scoreThreshold: newThreshold,
      );

      emit(SearchLoaded(
        query: state.query,
        threshold: newThreshold,
        topK: state.topK,
        results: response.results,
        isEmpty: response.results.isEmpty,
      ));
    } catch (e) {
      emit(SearchFailure(
        error: _parseError(e),
        query: state.query,
        threshold: newThreshold,
        topK: state.topK,
      ));
    }
  }

  Future<void> _onTopKChanged(
    TopKChanged event,
    Emitter<SearchState> emit,
  ) async {
    final newTopK = event.topK;
    if (state.query.trim().isEmpty) {
      emit(SearchInitial(
        query: state.query,
        threshold: state.threshold,
        topK: newTopK,
      ));
      return;
    }

    emit(SearchLoading(
      query: state.query,
      threshold: state.threshold,
      topK: newTopK,
    ));

    try {
      final response = await _searchRepository.search(
        query: state.query.trim(),
        topK: newTopK,
        scoreThreshold: state.threshold,
      );

      emit(SearchLoaded(
        query: state.query,
        threshold: state.threshold,
        topK: newTopK,
        results: response.results,
        isEmpty: response.results.isEmpty,
      ));
    } catch (e) {
      emit(SearchFailure(
        error: _parseError(e),
        query: state.query,
        threshold: state.threshold,
        topK: newTopK,
      ));
    }
  }

  void _onSearchCleared(SearchCleared event, Emitter<SearchState> emit) {
    _debounceTimer?.cancel();
    emit(SearchInitial(
      query: '',
      threshold: state.threshold,
      topK: state.topK,
    ));
  }

  String _parseError(dynamic error) {
    if (error is DioException) {
      if (error.response?.data is Map) {
        final data = error.response!.data as Map<String, dynamic>;
        if (data['detail'] != null) return data['detail'].toString();
        if (data['error'] != null) return data['error'].toString();
      }
      return error.message ?? 'Search request failed.';
    }
    return error.toString();
  }
}
