//
//  ParakeetService.swift
//  Starling
//
//  Created by Ryan D'Onofrio on 10/11/25.
//

import FluidAudio
import Foundation
import os

actor ParakeetService {
    enum ServiceError: Error {
        case unavailable
    }

    private enum State {
        case idle
        case initializing
        case ready
    }

    private var state: State = .idle
    private var manager: AsrManager?
    private let logger = Logger(subsystem: "com.parakeet.Starling", category: "ParakeetService")

    func prepareIfNeeded(progress: (@Sendable (Double) async -> Void)? = nil) async throws {
        switch state {
        case .ready:
            return
        case .initializing:
            // Wait for ongoing initialization to complete
            while state == .initializing {
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            if state != .ready {
                throw ServiceError.unavailable
            }
            return
        case .idle:
            break
        }

        state = .initializing
        if let progress {
            await progress(0.0)
        }
        do {
            let models = try await AsrModels.downloadAndLoad(version: .v3)
            if let progress {
                await progress(1.0)
            }
            let manager = AsrManager(config: .default)
            try await manager.initialize(models: models)
            self.manager = manager
            state = .ready
            logger.log("Parakeet service ready")
        } catch is CancellationError {
            state = .idle
            throw ServiceError.unavailable
        } catch {
            state = .idle
            logger.error("Failed to initialise Parakeet service: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    func transcribe(samples: [Float], sampleRate: Double) async throws -> String {
        guard !samples.isEmpty else { return "" }
        let wasReady = state == .ready
        let warmupStart = CFAbsoluteTimeGetCurrent()
        try await prepareIfNeeded(progress: nil)
        if !wasReady && state == .ready {
            let warmupMs = Int((CFAbsoluteTimeGetCurrent() - warmupStart) * 1000)
            logger.log("⏱️ Cold start: model warmup took \(warmupMs, privacy: .public)ms")
        } else if wasReady {
            logger.log("⏱️ Warm start: model already ready")
        }
        guard let manager else {
            throw ServiceError.unavailable
        }
        if sampleRate != 16_000 {
            logger.warning("Unexpected sample rate: \(sampleRate, privacy: .public)")
        }
        let result = try await manager.transcribe(samples)
        return result.text
    }
}
