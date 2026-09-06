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
    private let weights: KindWeights
    private let vectors: [CharacteristicVector]
    private let magnitudes: [Double]

    init(vectors: [CharacteristicVector], useRarityWeighting: Bool) {
        let resolved = useRarityWeighting ? KindWeights.rarity(over: vectors) : .uniform
        self.weights = resolved
        self.vectors = vectors
        self.magnitudes = vectors.map(resolved.magnitude(of:))
    }

    /// The weighted magnitude of fragment `index` — its size in the units the
    /// similarity is measured in, which is what the size prune needs.
    func magnitude(_ index: Int) -> Double {
        magnitudes[index]
    }

    func similarity(_ lhs: Int, _ rhs: Int) -> Double {
        weights.similarity(
            vectors[lhs],
            vectors[rhs],
            magnitude: magnitudes[lhs],
            magnitudes[rhs]
        )
    }
}
