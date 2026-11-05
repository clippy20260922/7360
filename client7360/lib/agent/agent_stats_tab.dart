import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'agent_models.dart';
import 'agent_service.dart';
import 'agent_theme.dart';
import 'agent_widgets.dart';

/// Onglet « Stats » : indicateurs clés, répartition, retards, tendance.
class AgentStatsTab extends StatelessWidget {
  const AgentStatsTab({super.key, required this.controller});

  final AgentController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final snap = controller.snapshot;
        if (snap == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final st = snap.stats;

        return RefreshIndicator(
          onRefresh: controller.refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
            children: [
              Row(
                children: [
                  Expanded(
                    child: _Kpi(
                      icon: Icons.pie_chart_rounded,
                      label: "Taux d'occupation",
                      value: formatPercent(st.occupancyRate),
                      sub: '${st.occupied} / ${st.total} places',
                      color: AgentColors.blue,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _Kpi(
                      icon: Icons.verified_rounded,
                      label: 'Véhicules en règle',
                      value: formatPercent(st.complianceRate),
                      sub: '${st.compliant} / ${st.occupied} garés',
                      color: st.complianceRate >= 0.8
                          ? AgentColors.ok
                          : AgentColors.warn,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _Kpi(
                      icon: Icons.report_problem_rounded,
                      label: 'Infractions',
                      value: '${st.violations}',
                      sub: '${st.overtime} dépassements · ${st.unpaid} non payés',
                      color: st.violations == 0
                          ? AgentColors.ok
                          : AgentColors.bad,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _Kpi(
                      icon: Icons.timer_rounded,
                      label: 'Retard moyen',
                      value: st.overtime == 0
                          ? '—'
                          : formatDuration(st.avgOvertime),
                      sub: st.expiring == 0
                          ? 'Aucune échéance proche'
                          : '${st.expiring} expirent < 10 min',
                      color: AgentColors.warn,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _Section(
                title: 'Répartition des places',
                child: _Distribution(stats: st),
              ),
              const SizedBox(height: 16),
              _Section(
                title: 'Occupation par catégorie',
                child: Column(
                  children: [
                    for (final c in st.categories) _CategoryBar(stat: c),
                    if (st.lotsTotal > 0)
                      _CategoryBar(
                        stat: CategoryStat(
                          'Parkings complets',
                          Icons.local_parking_rounded,
                          st.lotsFull,
                          st.lotsTotal,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _Section(
                title: 'Gravité des infractions',
                child: _BucketChart(buckets: st.buckets),
              ),
              const SizedBox(height: 16),
              _Section(
                title: "Occupation (depuis l'ouverture)",
                child: SizedBox(
                  height: 90,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: _SparklinePainter(controller.occupancyHistory),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ───────────────────────── Blocs ─────────────────────────

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AgentCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(title),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({
    required this.icon,
    required this.label,
    required this.value,
    required this.sub,
    required this.color,
  });

  final IconData icon;
  final String label, value, sub;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AgentCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              color: AgentColors.ink,
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: AgentColors.ink,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            sub,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AgentColors.muted, fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── Anneau de répartition ─────────────────────────

class _Distribution extends StatelessWidget {
  const _Distribution({required this.stats});

  final AgentStats stats;

  @override
  Widget build(BuildContext context) {
    final inOrder = stats.compliant;
    final parts = <(String, int, Color)>[
      ('Libres', stats.free, const Color(0xFF34C759)),
      ('Occupées en règle', inOrder, AgentColors.blue),
      ('Occupées en infraction', stats.violations, AgentColors.bad),
      ('Réservées', stats.reserved, const Color(0xFFFFB020)),
    ];

    return Row(
      children: [
        SizedBox(
          width: 130,
          height: 130,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: const Size.square(130),
                painter: _DonutPainter(
                  [for (final p in parts) p.$2.toDouble()],
                  [for (final p in parts) p.$3],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    formatPercent(stats.occupancyRate),
                    style: const TextStyle(
                      color: AgentColors.ink,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Text(
                    'occupé',
                    style: TextStyle(color: AgentColors.muted, fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            children: [
              for (final p in parts)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: p.$3,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          p.$1,
                          style: const TextStyle(
                            color: AgentColors.ink,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        '${p.$2}',
                        style: const TextStyle(
                          color: AgentColors.ink,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.values, this.colors);

  final List<double> values;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 18.0;
    final rect = Offset(stroke / 2, stroke / 2) &
        Size(size.width - stroke, size.height - stroke);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = AgentColors.line;
    canvas.drawArc(rect, 0, math.pi * 2, false, base);

    final total = values.fold<double>(0, (a, b) => a + b);
    if (total <= 0) return;
    final visible = values.where((v) => v > 0).length;
    final gap = visible > 1 ? 0.05 : 0.0;

    var start = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      if (values[i] <= 0) continue;
      final sweep = values[i] / total * math.pi * 2;
      canvas.drawArc(
        rect,
        start + gap / 2,
        math.max(sweep - gap, 0.001),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.butt
          ..color = colors[i],
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) => true;
}

// ───────────────────────── Barres de catégories ─────────────────────────

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({required this.stat});

  final CategoryStat stat;

  @override
  Widget build(BuildContext context) {
    final color = stat.rate >= 0.9
        ? AgentColors.bad
        : stat.rate >= 0.7
            ? AgentColors.warn
            : AgentColors.blue;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          Row(
            children: [
              Icon(stat.icon, size: 18, color: AgentColors.muted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  stat.label,
                  style: const TextStyle(
                    color: AgentColors.ink,
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
              ),
              Text(
                '${stat.occupied}/${stat.total} · ${formatPercent(stat.rate)}',
                style: const TextStyle(
                  color: AgentColors.muted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: stat.rate,
              minHeight: 8,
              color: color,
              backgroundColor: AgentColors.line,
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── Histogramme de gravité ─────────────────────────

class _BucketChart extends StatelessWidget {
  const _BucketChart({required this.buckets});

  final List<int> buckets;

  static const _labels = ['< 15 min', '15 min–1 h', '1–3 h', '> 3 h', 'Non payé'];

  @override
  Widget build(BuildContext context) {
    final maxV = math.max(1, buckets.reduce(math.max));
    const barArea = 90.0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < buckets.length; i++)
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${buckets[i]}',
                  style: const TextStyle(
                    color: AgentColors.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  height: math.max(4, barArea * buckets[i] / maxV),
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    color: Color.lerp(
                      AgentColors.warn,
                      AgentColors.bad,
                      i / (buckets.length - 1),
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _labels[i],
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AgentColors.muted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ───────────────────────── Courbe d'occupation ─────────────────────────

class _SparklinePainter extends CustomPainter {
  _SparklinePainter(this.values);

  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = AgentColors.line
      ..strokeWidth = 1;
    for (var i = 0; i < 3; i++) {
      final y = size.height * i / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (values.length < 2) {
      final tp = TextPainter(
        text: const TextSpan(
          text: 'La courbe se construit au fil des actualisations…',
          style: TextStyle(color: AgentColors.muted, fontSize: 12),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width);
      tp.paint(canvas, Offset(0, size.height / 2 - tp.height / 2));
      return;
    }

    final lo = values.reduce(math.min), hi = values.reduce(math.max);
    final span = math.max(hi - lo, 0.05);
    final min = math.max(0.0, lo - span * 0.2);
    final max = hi + span * 0.2;

    Offset pt(int i) => Offset(
          size.width * i / (values.length - 1),
          size.height * (1 - (values[i] - min) / (max - min)),
        );

    final line = Path()..moveTo(pt(0).dx, pt(0).dy);
    for (var i = 1; i < values.length; i++) {
      line.lineTo(pt(i).dx, pt(i).dy);
    }
    final fill = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AgentColors.blue.withValues(alpha: 0.28),
            AgentColors.blue.withValues(alpha: 0.0),
          ],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = AgentColors.blue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawCircle(pt(values.length - 1), 4.5, Paint()..color = AgentColors.blue);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter old) => true;
}
