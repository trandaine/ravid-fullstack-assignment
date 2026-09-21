import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_banner.dart';
import '../../../core/widgets/loading_indicator.dart';
import '../bloc/search_bloc.dart';
import '../bloc/search_event.dart';
import '../bloc/search_state.dart';
import 'widgets/search_result_card.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  bool _showFilters = false;

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) {
        context.read<SearchBloc>().add(SearchQueryChanged(query: query));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vector Search'),
        actions: [
          IconButton(
            icon: Icon(
              _showFilters ? Icons.tune : Icons.tune_outlined,
              color: _showFilters ? Theme.of(context).colorScheme.primary : null,
            ),
            tooltip: 'Search Filters',
            onPressed: () {
              setState(() {
                _showFilters = !_showFilters;
              });
            },
          ),
        ],
      ),
      body: BlocBuilder<SearchBloc, SearchState>(
        builder: (context, state) {
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search ingested knowledge base...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              context.read<SearchBloc>().add(const SearchCleared());
                            },
                          )
                        : null,
                  ),
                  onChanged: (val) {
                    setState(() {});
                    _onQueryChanged(val);
                  },
                  onSubmitted: (val) {
                    _debounce?.cancel();
                    context.read<SearchBloc>().add(SearchQueryChanged(query: val));
                  },
                ),
              ),
              if (_showFilters) _buildFiltersCard(context, state),
              if (state is SearchFailure)
                ErrorBanner(
                  message: state.error,
                  onRetry: () {
                    context.read<SearchBloc>().add(
                          SearchQueryChanged(query: _searchController.text),
                        );
                  },
                ),
              Expanded(
                child: _buildBody(state),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFiltersCard(BuildContext context, SearchState state) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: 0,
      color: Colors.grey[50],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey[200]!),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Score Threshold: ${(state.threshold * 100).toInt()}%',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                Text(
                  state.threshold.toStringAsFixed(2),
                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                ),
              ],
            ),
            Slider(
              value: state.threshold,
              min: 0.0,
              max: 1.0,
              divisions: 20,
              onChanged: (val) {
                context.read<SearchBloc>().add(ThresholdChanged(threshold: val));
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Top Results (k):',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                DropdownButton<int>(
                  value: state.topK,
                  isDense: true,
                  items: [1, 3, 5, 10, 20].map((int val) {
                    return DropdownMenuItem<int>(
                      value: val,
                      child: Text('$val'),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      context.read<SearchBloc>().add(TopKChanged(topK: val));
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(SearchState state) {
    if (state is SearchLoading) {
      return const LoadingIndicator(message: 'Searching vectors...');
    }

    if (state is SearchInitial) {
      return const EmptyState(
        icon: Icons.manage_search_outlined,
        message: 'Type a query above to search through indexed documents.',
      );
    }

    if (state is SearchLoaded) {
      if (state.isEmpty) {
        return const EmptyState(
          icon: Icons.search_off_outlined,
          message: 'No matching chunks found above the score threshold.',
        );
      }

      return ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: state.results.length,
        itemBuilder: (context, index) {
          final result = state.results[index];
          return SearchResultCard(result: result);
        },
      );
    }

    return const SizedBox.shrink();
  }
}
