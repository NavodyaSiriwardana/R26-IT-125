import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:frontend/app_state.dart';
import 'package:frontend/components/self_bias_identification/screens/bias_result_screen.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:frontend/components/self_bias_identification/services/api_service.dart';

class AllEntriesScreen extends StatefulWidget {
  const AllEntriesScreen({super.key});

  @override
  State<AllEntriesScreen> createState() => _AllEntriesScreenState();
}

class _AllEntriesScreenState extends State<AllEntriesScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _entries = [];

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  Future<void> _loadEntries() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/api/bias/history/${AppState.userId}'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final history = data['history'] as List? ?? [];

        history.sort((a, b) {
          final aId = a['entry_id']?.toString() ?? '';
          final bId = b['entry_id']?.toString() ?? '';
          final aTime = int.tryParse(aId.replaceAll(RegExp(r'\D'), '')) ?? 0;
          final bTime = int.tryParse(bId.replaceAll(RegExp(r'\D'), '')) ?? 0;
          return bTime.compareTo(aTime);
        });

        setState(() {
          _entries = history.map((e) => e as Map<String, dynamic>).toList();
        });
      }
    } catch (e) {
      print('All entries load error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Color _scoreColor(int pas) {
    if (pas >= 70) return const Color(0xFF4ADE80);
    if (pas >= 50) return const Color(0xFFFFB74D);
    return const Color(0xFFFF6B6B);
  }

  String _formatBiasType(String type) {
    if (type.isEmpty) return 'Unknown';
    if (type == 'accurate_perception') return 'Accurate Perception';
    return type
        .split('_')
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E14),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('All Entries', style: GoogleFonts.outfit(fontSize: 19, fontWeight: FontWeight.w700)),
            Text('${_entries.length} diary records', style: const TextStyle(fontSize: 12, color: Colors.white54)),
          ],
        ),
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(color: Color(0xFF0A0E14)),
      child: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF7B6EFF)))
          : _entries.isEmpty
              ? const Center(child: Text('No entries yet', style: TextStyle(color: Colors.white54, fontSize: 16)))
              : RefreshIndicator(
                  color: const Color(0xFF7B6EFF),
                  onRefresh: _loadEntries,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    itemCount: _entries.length,
                    itemBuilder: (context, index) {
                      final entry = _entries[index];
                      final pas = entry['pas_score'] ?? 0;
                      final bias = entry['primary_bias']?['bias_type'] ?? '';
                      final entryId = entry['entry_id'] ?? '';
                      final color = _scoreColor(pas);

                      return HoverCard(
                        entry: entry,
                        pas: pas,
                        biasType: _formatBiasType(bias),
                        entryId: entryId,
                        color: color,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => BiasResultScreen(result: entry),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
      ),
    );
  }
}

// New Hoverable Card Widget
class HoverCard extends StatefulWidget {
  final Map<String, dynamic> entry;
  final int pas;
  final String biasType;
  final String entryId;
  final Color color;
  final VoidCallback onTap;

  const HoverCard({
    super.key,
    required this.entry,
    required this.pas,
    required this.biasType,
    required this.entryId,
    required this.color,
    required this.onTap,
  });

  @override
  State<HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<HoverCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.only(bottom: 12),
          transform: Matrix4.translationValues(0, _isHovered ? -4 : 0, 0),
          decoration: BoxDecoration(
            color: _isHovered
                ? Color.alphaBlend(
                    widget.color.withOpacity(0.14),
                    const Color(0xFF141428),
                  )
                : const Color(0xFF141428),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _isHovered ? widget.color.withOpacity(0.5) : Colors.white.withOpacity(0.06),
              width: _isHovered ? 1.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: _isHovered ? widget.color.withOpacity(0.25) : Colors.black.withOpacity(0.3),
                blurRadius: _isHovered ? 20 : 8,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.biasType,
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.entryId,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.4),
                        ),
                      ),
                      if (_isHovered) ...[
                        const SizedBox(height: 8),
                        Text(
                          "Tap to view full analysis →",
                          style: TextStyle(
                            fontSize: 11.5,
                            color: widget.color,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        widget.color,
                        Color.lerp(widget.color, Colors.black, 0.35)!,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: widget.color.withOpacity(_isHovered ? 0.55 : 0.35),
                        blurRadius: _isHovered ? 20 : 14,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Text(
                    '${widget.pas}',
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}