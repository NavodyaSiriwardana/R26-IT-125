import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:frontend/components/self_bias_identification/screens/weekly_trends_screen.dart';
import 'package:frontend/components/self_bias_identification/widgets/gradient_ring_painter.dart';

class BiasResultScreen extends StatefulWidget {
  final Map<String, dynamic> result;
  const BiasResultScreen({super.key, required this.result});

  @override
  State<BiasResultScreen> createState() => _BiasResultScreenState();
}

class _BiasResultScreenState extends State<BiasResultScreen> {
  static const _accent = Color(0xFF7B6EFF);
  static const _accent2 = Color(0xFFB2A8FF);
  static const _green = Color(0xFF4ADE80);
  static const _red = Color(0xFFFF6B6B);
  static const _orange = Color(0xFFFFB74D);
  static const _blue = Color(0xFF60A5FA);
  static const _cardColor = Color(0xFF141428);

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    final primaryBias = result['primary_bias'] as Map? ?? {};
    final biasType = primaryBias['bias_type'] ?? '';
    final confidence = primaryBias['confidence'] ?? 0.0;
    final pasScore = result['pas_score'] ?? 0;
    final pasLevel = result['pas_level'] ?? '';
    final comparison = result['comparison'] as Map? ?? {};
    final indicators = result['additional_indicators'] as List? ?? [];
    final explanation = primaryBias['explanation'] as List? ?? [];
    final reflection = result['reflection_text'] ?? '';
    final actions = result['suggested_actions'] as List? ?? [];
    final isRecurring = result['is_recurring'] == true;
    final streakCount = (result['streak_count'] as num?)?.toInt() ?? 1;

    final bool isAccurate = biasType == 'accurate_perception';
    final pasColor = pasScore >= 70
        ? _green
        : pasScore >= 50
        ? _orange
        : _red;
    final badgeColor = isAccurate ? _green : _red;

    final sections = <Widget>[
      _heroCard(
        isAccurate: isAccurate,
        badgeColor: badgeColor,
        biasType: biasType,
        confidence: (confidence as num).toDouble(),
        pasScore: (pasScore as num).toInt(),
        pasLevel: pasLevel.toString(),
        pasColor: pasColor,
        comparison: comparison,
        isRecurring: isRecurring,
        streakCount: streakCount,
      ),
      if (explanation.isNotEmpty) _explanationCard(explanation),
      _facialCheckCard(
        comparison['facial_emotion'] as Map<String, dynamic>?,
        indicators.any(
          (ind) => ind is Map && ind['type'] == 'facial_stress_mismatch',
        ),
      ),
      if (indicators.isNotEmpty) _indicatorsCard(indicators),
      if (reflection.toString().trim().isNotEmpty)
        _reflectionCard(reflection.toString()),
      _actionsCard(actions, isRecurring),
      _trendsButton(context),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E14),
      appBar: _glassAppBar(context, result['entry_id']?.toString() ?? ''),
      body: DecoratedBox(
        decoration: const BoxDecoration(color: Color(0xFF0A0E14)),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
          child: Column(
            children: [
              for (int i = 0; i < sections.length; i++) ...[
                sections[i],
                if (i != sections.length - 1) const SizedBox(height: 16),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ==================== App Bar ====================

  PreferredSizeWidget _glassAppBar(BuildContext context, String entryId) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight + 8),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF10141F),
          border: Border(
            bottom: BorderSide(color: Color(0x14FFFFFF)),
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: [
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_back_ios_new,
                        color: Colors.white,
                        size: 18,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            _accent.withValues(alpha: 0.9),
                            _accent2.withValues(alpha: 0.6),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(11),
                        boxShadow: [
                          BoxShadow(
                            color: _accent.withValues(alpha: 0.35),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.psychology_alt_rounded,
                        size: 18,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'TruthLens Analysis',
                            style: GoogleFonts.outfit(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          if (entryId.isNotEmpty)
                            Text(
                              entryId,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: Colors.white.withValues(alpha: 0.4),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                ),
              ),
            ),
          ),
    );
  }

  // ==================== Hero Card ====================

  Widget _heroCard({
    required bool isAccurate,
    required Color badgeColor,
    required String biasType,
    required double confidence,
    required int pasScore,
    required String pasLevel,
    required Color pasColor,
    required Map comparison,
    required bool isRecurring,
    required int streakCount,
  }) {
    return _glassCard(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _statusBadge(isAccurate, badgeColor),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.model_training_rounded,
                      size: 12,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'XGBoost',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: Colors.white.withValues(alpha: 0.5),
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            _formatBiasType(biasType),
            style: GoogleFonts.outfit(
              fontSize: 21,
              fontWeight: FontWeight.w800,
              height: 1.15,
              letterSpacing: -0.3,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.bolt_rounded, size: 15, color: _accent2),
              const SizedBox(width: 3),
              Text(
                '${(confidence * 100).toStringAsFixed(1)}% confidence',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.55),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          if (isRecurring) ...[
            const SizedBox(height: 14),
            _streakBanner(streakCount),
          ],
          const SizedBox(height: 22),
          Center(child: _pasGauge(pasScore, pasLevel, pasColor)),
          _divider(),
          _sectionLabel('Claimed vs Verified', icon: Icons.compare_arrows_rounded),
          const SizedBox(height: 16),
          _bar(
            Icons.schedule_rounded,
            'Claimed study',
            (comparison['claimed_duration'] as num?)?.toInt() ?? 0,
            (comparison['claimed_duration'] as num?)?.toInt() ?? 1,
            _blue,
          ),
          _ExpandableBar(
            icon: Icons.menu_book_rounded,
            label: 'Verified educational',
            value: (comparison['verified_educational'] as num?)?.toInt() ?? 0,
            max: (comparison['claimed_duration'] as num?)?.toInt() ?? 1,
            color: _green,
            breakdown: Map<String, dynamic>.from(
              comparison['educational_breakdown'] ?? {},
            ),
          ),
          _ExpandableBar(
            icon: Icons.forum_rounded,
            label: 'Social media',
            value: (comparison['social_media_minutes'] as num?)?.toInt() ?? 0,
            max: (comparison['claimed_duration'] as num?)?.toInt() ?? 1,
            color: _red,
            breakdown: Map<String, dynamic>.from(
              comparison['social_media_breakdown'] ?? {},
            ),
          ),
          _ExpandableBar(
            icon: Icons.movie_creation_rounded,
            label: 'Entertainment',
            value: (comparison['entertainment_minutes'] as num?)?.toInt() ?? 0,
            max: (comparison['claimed_duration'] as num?)?.toInt() ?? 1,
            color: _orange,
            breakdown: Map<String, dynamic>.from(
              comparison['entertainment_breakdown'] ?? {},
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(bool isAccurate, Color badgeColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            badgeColor.withValues(alpha: 0.24),
            badgeColor.withValues(alpha: 0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: badgeColor.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: badgeColor.withValues(alpha: 0.18),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isAccurate ? Icons.verified_outlined : Icons.warning_amber_rounded,
            size: 16,
            color: badgeColor,
          ),
          const SizedBox(width: 6),
          Text(
            isAccurate ? 'Good Alignment' : 'Bias Detected',
            style: GoogleFonts.outfit(
              fontSize: 13,
              color: badgeColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// Shown when this bias type has repeated across recent entries
  /// (`is_recurring`/`streak_count` from reflection_bot.py's history-aware
  /// logic) — a plain repeat count isn't a template render, it comes
  /// straight from the API response.
  Widget _streakBanner(int streakCount) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _orange.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Text(
            '$streakCount×',
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _orange,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  fontSize: 11,
                  height: 1.4,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
                children: [
                  TextSpan(
                    text: '$streakCount entries in a row ',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const TextSpan(text: 'with this same pattern.'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Mirrors the gauge used on the home dashboard (ticks + gradient ring)
  /// so the "biometric" visual language stays consistent across screens.
  Widget _pasGauge(int pasScore, String pasLevel, Color pasColor) {
    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: pasColor.withValues(alpha: 0.30),
                    blurRadius: 50,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
            const SizedBox(
              width: 140,
              height: 140,
              child: CustomPaint(painter: RingTicksPainter()),
            ),
            SizedBox(
              width: 104,
              height: 104,
              child: CustomPaint(
                painter: GradientRingPainter(
                  progress: pasScore / 100,
                  colors: [pasColor.withValues(alpha: 0.75), pasColor],
                  strokeWidth: 8.5,
                  glowDot: true,
                ),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$pasScore',
                  style: GoogleFonts.outfit(
                    fontSize: 36,
                    height: 1,
                    fontWeight: FontWeight.w800,
                    color: pasColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'out of 100',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: Colors.white.withValues(alpha: 0.4),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: pasColor.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: pasColor.withValues(alpha: 0.28)),
          ),
          child: Text(
            pasLevel.isEmpty ? 'Analyzed' : pasLevel,
            style: GoogleFonts.outfit(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: pasColor,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'SAS Score · Target 70+',
          style: TextStyle(
            fontSize: 11,
            color: Colors.white.withValues(alpha: 0.35),
          ),
        ),
      ],
    );
  }

  // ==================== Glass Card Primitive ====================

  Widget _glassCard({required Widget child, EdgeInsetsGeometry? padding}) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 32,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _sectionLabel(String text, {IconData? icon}) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 13, color: Colors.white.withValues(alpha: 0.45)),
          const SizedBox(width: 6),
        ],
        Text(
          text.toUpperCase(),
          style: GoogleFonts.outfit(
            fontSize: 11,
            color: Colors.white.withValues(alpha: 0.45),
            letterSpacing: 0.8,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _divider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Container(
        height: 1,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.transparent,
              Colors.white.withValues(alpha: 0.12),
              Colors.transparent,
            ],
          ),
        ),
      ),
    );
  }

  Widget _iconChip(IconData icon, Color color, {double size = 26}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: size * 0.52, color: color),
    );
  }

  Widget _bar(IconData icon, String label, int value, int max, Color color) {
    final ratio = max > 0 ? value / max : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        children: [
          Row(
            children: [
              _iconChip(icon, color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Colors.white.withValues(alpha: 0.65),
                  ),
                ),
              ),
              Text(
                '$value min',
                style: TextStyle(
                  fontSize: 12.5,
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio.clamp(0.0, 1.0),
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              valueColor: AlwaysStoppedAnimation(color),
              minHeight: 7,
            ),
          ),
        ],
      ),
    );
  }

  // ==================== Indicators Card ====================

  Widget _indicatorsCard(List indicators) {
    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('Additional Indicators', icon: Icons.report_gmailerrorred_rounded),
          const SizedBox(height: 14),
          ...indicators.map(
            (ind) => _indicatorRow(ind['type'] ?? '', ind['reason'] ?? ''),
          ),
        ],
      ),
    );
  }

  Widget _indicatorRow(String type, String reason) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _iconChip(Icons.priority_high_rounded, _red, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatBiasType(type),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  reason,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: Colors.white.withValues(alpha: 0.5),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: _red.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'Detected',
              style: TextStyle(fontSize: 10, color: _red, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== Why This Result ====================
  // Per-prediction feature contributions (XGBoost SHAP values) for the
  // class that was actually predicted — different from a generic
  // "feature importance" chart, this explains THIS entry specifically.

  Widget _explanationCard(List explanation) {
    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('Why this result?', icon: Icons.insights_rounded),
          const SizedBox(height: 4),
          Text(
            'What most influenced this specific prediction',
            style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.4)),
          ),
          const SizedBox(height: 16),
          ...explanation.map((e) => _explanationRow(e as Map)),
        ],
      ),
    );
  }

  Widget _explanationRow(Map e) {
    final feature = (e['feature'] ?? '').toString();
    final direction = (e['direction'] ?? '').toString();
    final weight = ((e['weight'] ?? 0) as num).toDouble();
    final increased = direction == 'increased';
    final color = increased ? _accent2 : _blue;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                increased ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                size: 13,
                color: color,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  feature,
                  style: const TextStyle(fontSize: 13.5, color: Colors.white70),
                ),
              ),
              Text(
                '${(weight * 100).round()}%',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: weight.clamp(0.0, 1.0),
              backgroundColor: Colors.white.withValues(alpha: 0.07),
              valueColor: AlwaysStoppedAnimation(color),
              minHeight: 5,
            ),
          ),
        ],
      ),
    );
  }

  // ==================== Facial Check ====================

  Widget _facialCheckCard(
    Map<String, dynamic>? facialEmotion,
    bool hasMismatch,
  ) {
    final captured =
        facialEmotion != null && facialEmotion['status'] == 'success';

    if (!captured) {
      return _glassCard(
        child: Row(
          children: [
            _iconChip(Icons.face_retouching_off_outlined, Colors.white.withValues(alpha: 0.35), size: 30),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Facial check skipped for this entry',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final dominant = (facialEmotion['dominant_emotion'] ?? '').toString();
    final stress = (facialEmotion['stress_indicator'] ?? 0.0) as num;
    const negativeEmotions = ['sad', 'angry', 'fear', 'disgust'];
    final isNegative = negativeEmotions.contains(dominant.toLowerCase());
    final color = isNegative ? _red : _green;
    final emoji = isNegative ? '😔' : '😊';
    final dominantLabel = dominant.isEmpty
        ? 'Unknown'
        : dominant[0].toUpperCase() + dominant.substring(1);

    return _glassCard(
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Center(
              child: Text(emoji, style: const TextStyle(fontSize: 18)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionLabel('Facial Check', icon: Icons.face_rounded),
                const SizedBox(height: 5),
                Text(
                  '$dominantLabel detected',
                  style: GoogleFonts.outfit(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${(stress * 100).round()}% stress signal · captured at diary entry',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.45),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withValues(alpha: 0.28)),
            ),
            child: Text(
              hasMismatch ? 'DIFFERS FROM MOOD' : 'MATCHES MOOD',
              style: TextStyle(
                fontSize: 8.5,
                fontWeight: FontWeight.w800,
                color: color,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== Reflection ====================

  Widget _reflectionCard(String reflection) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Color.alphaBlend(_orange.withValues(alpha: 0.11), _cardColor),
        borderRadius: BorderRadius.circular(24),
        border: const Border(
          left: BorderSide(color: _orange, width: 4),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 32,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -6,
            top: -14,
            child: Icon(
              Icons.format_quote_rounded,
              size: 64,
              color: _orange.withValues(alpha: 0.10),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_awesome_rounded, size: 13, color: _orange),
                  const SizedBox(width: 6),
                  Text(
                    'TRUTHLENS AI REFLECTION',
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      color: _orange,
                      letterSpacing: 1,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                reflection,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.6,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==================== Suggested Actions ====================

  Widget _actionsCard(List actions, bool isRecurring) {
    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _sectionLabel('Suggested Actions', icon: Icons.checklist_rounded),
              if (isRecurring)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: _accent2.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _accent2.withValues(alpha: 0.28)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.autorenew_rounded, size: 11, color: _accent2),
                      const SizedBox(width: 4),
                      Text(
                        'Updated',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: _accent2,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          ...actions.asMap().entries.map((e) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [_accent, _accent2],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '${e.key + 1}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        e.value.toString(),
                        style: const TextStyle(
                          fontSize: 15.5,
                          color: Colors.white70,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ==================== CTA ====================

  Widget _trendsButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const WeeklyTrendsScreen()),
          ),
          child: Ink(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_accent, Color(0xFF5B4FE0)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: _accent.withValues(alpha: 0.4),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'View Weekly Trends',
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward_rounded, size: 18, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatBiasType(String type) {
    if (type.isEmpty) return 'Unknown';
    return type
        .split('_')
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }
}

/// Maps a friendly app name (see sensor_data_service.dart's
/// `_friendlyNames`) to a recognizable icon + brand-ish color, so the
/// per-app breakdown reads at a glance instead of everything sharing one
/// plain dot. Bundled Material glyphs, not real fetched app icons — no
/// new package or device permission required.
({IconData icon, Color color}) _appIconFor(String appName) {
  final lower = appName.toLowerCase();
  if (lower.contains('youtube')) {
    return (icon: Icons.play_arrow_rounded, color: const Color(0xFFFF0000));
  }
  if (lower.contains('meet')) {
    return (icon: Icons.videocam_rounded, color: const Color(0xFF00832D));
  }
  if (lower.contains('tiktok') || lower.contains('musically')) {
    return (icon: Icons.music_note_rounded, color: Colors.black);
  }
  if (lower.contains('instagram')) {
    return (icon: Icons.camera_alt_rounded, color: const Color(0xFFDD2A7B));
  }
  if (lower.contains('facebook')) {
    return (icon: Icons.thumb_up_rounded, color: const Color(0xFF1877F2));
  }
  if (lower.contains('whatsapp')) {
    return (icon: Icons.chat_rounded, color: const Color(0xFF25D366));
  }
  if (lower.contains('twitter') || lower == 'x') {
    return (icon: Icons.alternate_email_rounded, color: Colors.black);
  }
  if (lower.contains('snapchat')) {
    return (icon: Icons.camera_rounded, color: const Color(0xFFFFFC00));
  }
  if (lower.contains('netflix')) {
    return (icon: Icons.smart_display_rounded, color: const Color(0xFFE50914));
  }
  if (lower.contains('spotify')) {
    return (icon: Icons.headphones_rounded, color: const Color(0xFF1DB954));
  }
  return (icon: Icons.apps_rounded, color: const Color(0xFF6B7280));
}

/// Same visual as a plain comparison bar, but tappable when a per-app
/// breakdown is available — expands to show which apps made up the total
/// (e.g. "YouTube: 30 min"), making the content-level app categorization
/// visible in the UI instead of only affecting the number silently.
class _ExpandableBar extends StatefulWidget {
  final IconData icon;
  final String label;
  final int value;
  final int max;
  final Color color;
  final Map<String, dynamic> breakdown;

  const _ExpandableBar({
    required this.icon,
    required this.label,
    required this.value,
    required this.max,
    required this.color,
    required this.breakdown,
  });

  @override
  State<_ExpandableBar> createState() => _ExpandableBarState();
}

class _ExpandableBarState extends State<_ExpandableBar> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final ratio = widget.max > 0 ? widget.value / widget.max : 0.0;
    final hasBreakdown = widget.breakdown.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: hasBreakdown
            ? () => setState(() => _expanded = !_expanded)
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(widget.icon, size: 13.5, color: widget.color),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          widget.label,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Colors.white.withValues(alpha: 0.65),
                          ),
                        ),
                      ),
                      if (hasBreakdown) ...[
                        const SizedBox(width: 3),
                        Icon(
                          _expanded
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                          size: 15,
                          color: Colors.white.withValues(alpha: 0.4),
                        ),
                      ],
                    ],
                  ),
                ),
                Text(
                  '${widget.value} min',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: widget.color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: ratio.clamp(0.0, 1.0),
                backgroundColor: Colors.white.withValues(alpha: 0.08),
                valueColor: AlwaysStoppedAnimation(widget.color),
                minHeight: 7,
              ),
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox(width: double.infinity),
              secondChild: Padding(
                padding: const EdgeInsets.only(top: 10, left: 36),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: widget.breakdown.entries.map((e) {
                    final minutes = (e.value as num).round();
                    final appIcon = _appIconFor(e.key);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 9),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Container(
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    color: appIcon.color,
                                    borderRadius: BorderRadius.circular(7),
                                  ),
                                  child: Icon(
                                    appIcon.icon,
                                    size: 12,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    e.key,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: Colors.white.withValues(alpha: 0.65),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '$minutes min',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.white.withValues(alpha: 0.45),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
              crossFadeState: _expanded && hasBreakdown
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 220),
              sizeCurve: Curves.easeOutCubic,
            ),
          ],
        ),
      ),
    );
  }
}
