import 'package:flutter/material.dart';

import 'agent_models.dart';
import 'agent_theme.dart';

/// Carte blanche arrondie avec ombre douce ; [accent] ajoute une barre de
/// couleur à gauche (sert à marquer le niveau de gravité).
class AgentCard extends StatelessWidget {
  const AgentCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.accent,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AgentColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AgentColors.line),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140B1B3A),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        children: [
          Padding(
            padding: padding.copyWith(
              left: padding.left + (accent != null ? 6 : 0),
            ),
            child: child,
          ),
          if (accent != null)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 6,
              child: ColoredBox(color: accent!),
            ),
        ],
      ),
    );
  }
}

/// Pastille « En règle / Dépassement / Non payé… ».
class ComplianceBadge extends StatelessWidget {
  const ComplianceBadge(this.compliance, {super.key, this.large = false});

  final Compliance compliance;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final c = compliance.color;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? 14 : 10,
        vertical: large ? 9 : 5,
      ),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: c.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(compliance.icon, size: large ? 20 : 15, color: c),
          SizedBox(width: large ? 8 : 5),
          Text(
            compliance.label,
            style: TextStyle(
              color: c,
              fontWeight: FontWeight.w800,
              fontSize: large ? 14 : 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// Plaque d'immatriculation française (bande bleue « F »).
class PlateBadge extends StatelessWidget {
  const PlateBadge(this.plate, {super.key});

  final String? plate;

  @override
  Widget build(BuildContext context) {
    if (plate == null) {
      return const Tag(Icons.help_outline_rounded, 'Plaque non fournie');
    }
    // « AB123CD » → « AB-123-CD » (format SIV)
    final m = RegExp(r'^([A-Z]{2})(\d{3})([A-Z]{2})$').firstMatch(plate!);
    final shown = m == null ? plate! : '${m[1]}-${m[2]}-${m[3]}';
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AgentColors.navy, width: 1.8),
      ),
      child: IntrinsicHeight(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 22,
              color: AgentColors.blue,
              alignment: Alignment.center,
              child: const Text(
                'F',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Text(
                shown,
                style: const TextStyle(
                  color: AgentColors.navy,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.8,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Petite pastille icône + texte.
class Tag extends StatelessWidget {
  const Tag(this.icon, this.text, {super.key, this.color = AgentColors.muted});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Étiquette de section en petites capitales.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: AgentColors.muted,
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
      ),
    );
  }
}

/// Tuile « icône / libellé / valeur ».
class InfoTile extends StatelessWidget {
  const InfoTile(this.icon, this.label, this.value, {super.key});

  final IconData icon;
  final String label, value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AgentColors.bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AgentColors.blue),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AgentColors.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AgentColors.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Range des [InfoTile] sur deux colonnes.
class TileGrid extends StatelessWidget {
  const TileGrid(this.tiles, {super.key});
  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = (c.maxWidth - 10) / 2;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [for (final t in tiles) SizedBox(width: w, child: t)],
      );
    });
  }
}
