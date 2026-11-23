// swift-tools-version: 6.2
// Offline Übersetzer & Transkription für macOS (Apple Silicon)

import PackageDescription

let package = Package(
    name: "OfflineTranslator",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "OfflineTranslator", targets: ["OfflineTranslator"])
    ],
    dependencies: [
        // Transkription: Whisper large-v3 via CoreML (GPU / Neural Engine)
        .package(url: "https://github.com/argmaxinc/WhisperKit", .upToNextMinor(from: "1.1.1")),
        // Transkription: NVIDIA Parakeet TDT (Ultra / v3) via CoreML
        .package(url: "https://github.com/FluidInference/FluidAudio", .upToNextMinor(from: "0.18.4")),
        // Übersetzung: TranslateGemma via MLX (Metal GPU)
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", .upToNextMinor(from: "3.33.0")),
        .package(url: "https://github.com/ml-explore/mlx-swift", .upToNextMinor(from: "0.33.0")),
        // Tokenizer für TranslateGemma
        .package(url: "https://github.com/huggingface/swift-transformers", .upToNextMinor(from: "1.4.0")),
    ],
    targets: [
        .executableTarget(
            name: "OfflineTranslator",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ],
            path: "Sources/OfflineTranslator",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
