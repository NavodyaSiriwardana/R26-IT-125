import 'package:flutter/material.dart';
import '../models/pattern_model.dart';
import '../services/pattern_service.dart';
import '../services/local_storage.dart';
import '../widgets/pattern_card.dart';
import '../widgets/evidence_bottom_sheet.dart';
import '../widgets/pattern_filter_chips.dart';
import '../widgets/empty_patterns_view.dart';

class MyPatternsScreen extends StatefulWidget {
  const MyPatternsScreen({super.key});

  @override
  State<MyPatternsScreen> createState() =>
      _MyPatternsScreenState();
}

class _MyPatternsScreenState extends State<MyPatternsScreen> {
  List<PatternModel> _allPatterns = [];
  List<PatternModel> _filteredPatterns = [];
  List<String> _dismissed = [];
  String _filter = 'All';
  bool _loading = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _analysePatterns();
  }

  Future<void> _analysePatterns() async {
    setState(() {
      _loading = true;
      _error = '';
    });

    final userId = await LocalStorage.getUserId();
    final patterns =
        await PatternService.analysePatterns(userId);

    setState(() {
      _loading = false;
      _allPatterns = patterns;
      _applyFilter(_filter);
    });

    if (patterns.isEmpty) {
      setState(() => _error = '');
    }
  }

  void _applyFilter(String filter) {
    setState(() {
      _filter = filter;
      List<PatternModel> base = _allPatterns
          .where((p) => !_dismissed.contains(p.insightText))
          .toList();

      if (filter == 'Strong') {
        _filteredPatterns = base
            .where((p) => p.patternLevel == 'Strong')
            .toList();
      } else if (filter == 'Moderate') {
        _filteredPatterns = base
            .where((p) => p.patternLevel == 'Moderate')
            .toList();
      } else if (filter == 'Cross-day') {
        _filteredPatterns = base
            .where((p) => p.dfsScore > 0)
            .toList();
      } else {
        _filteredPatterns = base;
      }
    });
  }

  void _showEvidence(PatternModel pattern) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => EvidenceBottomSheet(pattern: pattern),
    );
  }

  void _dismiss(PatternModel pattern) {
    setState(() {
      _dismissed.add(pattern.insightText);
      _applyFilter(_filter);
    });
  }

  @override
  Widget build(BuildContext context) {
    final strongCount = _allPatterns
        .where((p) => p.patternLevel == 'Strong')
        .length;
    final moderateCount = _allPatterns
        .where((p) => p.patternLevel == 'Moderate')
        .length;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A16),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded,
              color: Color(0xFF9784FF), size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'My Patterns',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              'Last 90 days • ${_allPatterns.length} patterns',
              style: const TextStyle(
                color: Color(0xFF5a5a7a),
                fontSize: 11,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _loading ? null : _analysePatterns,
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      color: Color(0xFF7B61FF),
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.refresh,
                    color: Color(0xFF7B61FF), size: 20),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 0.5,
            color: const Color(0xFF1e1e2e),
          ),
        ),
      ),
      body: Column(
        children: [
          const SizedBox(height: 12),
          if (_allPatterns.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16),
              child: Row(
                children: [
                  _statCard(
                    '${_allPatterns.length}',
                    'Patterns',
                    const Color(0xFF1DB954),
                  ),
                  const SizedBox(width: 8),
                  _statCard(
                    '$strongCount',
                    'Strong',
                    const Color(0xFF1DB954),
                  ),
                  const SizedBox(width: 8),
                  _statCard(
                    '$moderateCount',
                    'Moderate',
                    const Color(0xFFF5A623),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          PatternFilterChips(
            selected: _filter,
            onSelected: _applyFilter,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF7B61FF),
                    ),
                  )
                : _filteredPatterns.isEmpty
                    ? const EmptyPatternsView()
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16),
                        itemCount: _filteredPatterns.length,
                        itemBuilder: (context, index) {
                          final pattern =
                              _filteredPatterns[index];
                          return PatternCard(
                            pattern: pattern,
                            onSeeEvidence: () =>
                                _showEvidence(pattern),
                            onDismiss: () =>
                                _dismiss(pattern),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _statCard(
      String number, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color.withValues(alpha: 0.10), const Color(0xFF13132A)],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.12),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          children: [
            Text(
              number,
              style: TextStyle(
                color: color,
                fontSize: 21,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF8888AC),
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}