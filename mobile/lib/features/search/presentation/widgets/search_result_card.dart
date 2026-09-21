import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/models/search_result.dart';

class SearchResultCard extends StatelessWidget {
  final SourceChunk result;

  const SearchResultCard({super.key, required this.result});

  Color _getScoreColor(double score) {
    if (score >= 0.7) return Colors.green[700]!;
    if (score >= 0.5) return Colors.orange[800]!;
    return Colors.grey[700]!;
  }

  Color _getScoreBgColor(double score) {
    if (score >= 0.7) return Colors.green[50]!;
    if (score >= 0.5) return Colors.orange[50]!;
    return Colors.grey[100]!;
  }

  @override
  Widget build(BuildContext context) {
    final score = result.score;
    final scoreColor = _getScoreColor(score);
    final scoreBgColor = _getScoreBgColor(score);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      elevation: 0.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey[200]!),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(Icons.description, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          result.documentName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: scoreBgColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: scoreColor.withOpacity(0.3)),
                  ),
                  child: Text(
                    'Score: ${(score * 100).toStringAsFixed(1)}%',
                    style: TextStyle(
                      color: scoreColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 16),
            Text(
              result.content,
              style: TextStyle(
                color: Colors.grey[800],
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: result.content));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Chunk copied to clipboard'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
                icon: const Icon(Icons.copy, size: 14),
                label: const Text('Copy Chunk', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
