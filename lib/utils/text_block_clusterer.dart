/// One text observation from the OCR engine, with its bounding box in
/// normalised image coordinates (0..1, top-left origin).
class OcrObservation {
  const OcrObservation({
    required this.text,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.confidence,
  });

  final String text;
  final double x;
  final double y;
  final double width;
  final double height;
  final double confidence;

  double get top => y;
  double get bottom => y + height;
  double get left => x;
  double get right => x + width;
  double get area => width * height;

  factory OcrObservation.fromMap(Map<String, Object?> map) => OcrObservation(
        text: (map['text'] as String? ?? '').trim(),
        x: _toDouble(map['x']),
        y: _toDouble(map['y']),
        width: _toDouble(map['width']),
        height: _toDouble(map['height']),
        confidence: _toDouble(map['confidence']),
      );

  static double _toDouble(Object? v) {
    if (v is num) return v.toDouble();
    return 0.0;
  }
}

/// Heuristic: groups [observations] into clusters of vertically-adjacent
/// lines and returns the cluster with the largest total area. That cluster
/// is the typeset story paragraph; isolated labels inside the illustration
/// (small, scattered, distant from any other text) form their own tiny
/// clusters and are dropped.
///
/// Returns the picked observations in reading order (top-to-bottom, left-
/// to-right within a row). When there are very few observations the input
/// is returned unchanged.
List<OcrObservation> pickMainParagraph(
  List<OcrObservation> observations, {
  // Allowed vertical gap (as a fraction of image height) between two
  // observations that should belong to the same cluster. Picture-book
  // paragraphs have line-heights around 4–8% of the page height.
  double clusterGap = 0.06,
  // If the largest cluster covers less than this fraction of the total
  // observation area we don't trust it and return everything.
  double minClusterAreaShare = 0.30,
}) {
  if (observations.length <= 2) return observations;

  // 1. Sort observations top-to-bottom.
  final sorted = List<OcrObservation>.from(observations)
    ..sort((a, b) => a.top.compareTo(b.top));

  // 2. Group into clusters by vertical proximity. We compare the top of the
  //    candidate observation to the maximum bottom of the current cluster.
  final clusters = <List<OcrObservation>>[];
  for (final obs in sorted) {
    if (clusters.isEmpty) {
      clusters.add([obs]);
      continue;
    }
    final last = clusters.last;
    final lastBottom = last
        .map((o) => o.bottom)
        .fold<double>(0, (a, b) => a > b ? a : b);
    final gap = obs.top - lastBottom;
    if (gap > clusterGap) {
      clusters.add([obs]);
    } else {
      last.add(obs);
    }
  }

  // 3. Score each cluster by total area * count. Area alone is biased
  //    toward big-but-single observations; count alone toward tight blobs
  //    of small text. The product matches "real paragraphs" well.
  final scored = clusters
      .map(
        (c) => (
          cluster: c,
          score: c.map((o) => o.area).fold<double>(0, (a, b) => a + b) *
              c.length,
          area: c.map((o) => o.area).fold<double>(0, (a, b) => a + b),
        ),
      )
      .toList()
    ..sort((a, b) => b.score.compareTo(a.score));
  final best = scored.first;
  final bestCluster = best.cluster;

  // 4. Sanity guards: if the winning cluster doesn't actually dominate the
  //    page, the heuristic isn't reliable; return everything so downstream
  //    sanitising can still do its job.
  //    (a) Best cluster must cover ≥ minClusterAreaShare of total area.
  //    (b) Best cluster must be at least 1.5× larger than the runner-up.
  final totalArea =
      sorted.map((o) => o.area).fold<double>(0, (a, b) => a + b);
  if (totalArea > 0 && best.area / totalArea < minClusterAreaShare) {
    return sorted;
  }
  if (scored.length >= 2) {
    final runnerUp = scored[1];
    if (runnerUp.area > 0 && best.area / runnerUp.area < 1.5) {
      return sorted;
    }
  }

  // 5. Reorder the winning cluster into reading order. Observations whose
  //    tops are within ~1% of each other belong to the same visual line, in
  //    which case left-to-right wins; otherwise top-to-bottom.
  final reading = List<OcrObservation>.from(bestCluster)
    ..sort((a, b) {
      if ((a.top - b.top).abs() < 0.015) return a.left.compareTo(b.left);
      return a.top.compareTo(b.top);
    });
  return reading;
}

/// Joins picked observations into a single newline-separated string,
/// grouping ones at the same visual line into a single line of text.
String observationsToText(List<OcrObservation> observations) {
  if (observations.isEmpty) return '';
  final lines = <List<OcrObservation>>[];
  for (final obs in observations) {
    if (lines.isEmpty || (obs.top - lines.last.first.top).abs() > 0.015) {
      lines.add([obs]);
    } else {
      lines.last.add(obs);
    }
  }
  return lines
      .map(
        (line) => (line..sort((a, b) => a.left.compareTo(b.left)))
            .map((o) => o.text)
            .join(' '),
      )
      .join('\n');
}
