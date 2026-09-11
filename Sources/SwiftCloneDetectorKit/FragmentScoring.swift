//
//  FragmentScoring.swift
//  SwiftCloneDetectorKit
//
//  One run's weights and precomputed magnitudes, so a quadratic pass over
//  fragment pairs recomputes neither.
//

/// One run's scoring: the kind weights, and every fragment's weighted magnitude
/// computed once.
///
/// Similarity runs for every candidate pair, so a magnitude recomputed per call
/// would be recomputed a quadratic number of times.
struct FragmentScoring {
    /// Fewest fragments for "rare in this codebase" to mean anything. Below it,
    /// document frequency is a handful of observations and a floor built on it
    /// would be noise — among three fragments every kind looks ubiquitous.
    private static let minimumCorpusForRarity = 30

    private let ranked: [RankedVector]
    private let weightsAreRarity: Bool

    /// Whether ``distinctiveness(_:)`` carries information for this run.
    ///
    /// It does not under uniform weighting, where every kind weighs 1 and every
    /// fragment therefore scores exactly 1 — a floor above that would suppress
    /// the whole run rather than its least distinctive part. Nor does it on an
    /// input too small to have a shape.
    var rarityIsMeaningful: Bool {
        weightsAreRarity && ranked.count >= Self.minimumCorpusForRarity
    }

    init(vectors: [CharacteristicVector], useRarityWeighting: Bool) {
        let resolved = useRarityWeighting ? KindWeights.rarity(over: vectors) : .uniform
        // One ranking over the whole corpus, so every fragment's entries sort the
        // same way and two of them can be intersected by merging.
        let ranking = KindRanking(over: vectors)
        self.ranked = vectors.map { ranking.ranked($0, weights: resolved) }
        self.weightsAreRarity = useRarityWeighting
    }

    /// The weighted magnitude of fragment `index` — its size in the units the
    /// similarity is measured in, which is what the size prune needs.
    func magnitude(_ index: Int) -> Double {
        ranked[index].magnitude
    }

    /// How much distinguishing structure fragment `index` carries, as the mean
    /// weight of its node kinds.
    ///
    /// 1.0 means every kind it uses appears in every other fragment — it is built
    /// entirely from the constructs Swift code is always made of, so matching it
    /// against anything says nothing. Higher means it uses constructs most
    /// fragments do not.
    func distinctiveness(_ index: Int) -> Double {
        let total = ranked[index].total
        guard total > 0 else {
            return 0
        }
        return ranked[index].magnitude / Double(total)
    }

    func similarity(_ lhs: Int, _ rhs: Int) -> Double {
        RankedVector.similarity(ranked[lhs], ranked[rhs])
    }
}
