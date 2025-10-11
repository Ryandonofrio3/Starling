//
//  AudioCaptureController.swift
//  Starling
//
//  Created by Ryan D'Onofrio on 10/11/25.
//

import AVFoundation
import Foundation
import os

protocol AudioCaptureControllerDelegate: AnyObject {
    @MainActor
    func audioControllerDidStart(_ controller: AudioCaptureController)

    @MainActor
    func audioController(_ controller: AudioCaptureController, didProduce chunk: AudioChunk)

    @MainActor
    func audioControllerDidStop(_ controller: AudioCaptureController)

    @MainActor
    func audioController(_ controller: AudioCaptureController, didFailWith error: Error)
}

final class AudioCaptureController {
    enum State {
        case idle
        case starting
        case running
        case stopping
    }

    private let engine = AVAudioEngine()
    private let targetFormat: AVAudioFormat
    private let logger = Logger(subsystem: "com.parakeet.Starling", category: "AudioCapture")
    private let bufferSize: AVAudioFrameCount = 1024
    private let queue = DispatchQueue(label: "com.parakeet.audio-capture", qos: .userInitiated)
    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?

    weak var delegate: AudioCaptureControllerDelegate?

    private(set) var state: State = .idle

    init(sampleRate: Double = 16_000) {
        targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
    }

    func start() {
        guard state == .idle else {
            logger.debug("Ignored start request in state \(String(describing: self.state), privacy: .public)")
            return
        }

        state = .starting

        do {
            try configureSession()
        } catch {
            logger.error("Failed to configure audio session: \(error.localizedDescription, privacy: .public)")
            state = .idle
            notifyFailure(error)
            return
        }

        let inputNode = engine.inputNode
        let hardwareFormat = inputNode.outputFormat(forBus: 0)
        inputFormat = hardwareFormat

        if hardwareFormat.sampleRate != targetFormat.sampleRate || hardwareFormat.channelCount != targetFormat.channelCount {
            converter = AVAudioConverter(from: hardwareFormat, to: targetFormat)
        } else {
            converter = nil
        }

        let audioUnit = inputNode.auAudioUnit
        if audioUnit.maximumFramesToRender < bufferSize {
            audioUnit.maximumFramesToRender = bufferSize
        }

        installTap(on: inputNode)

        do {
            engine.prepare()
            try engine.start()
            state = .running
            notifyStart()
        } catch {
            logger.error("Failed to start audio engine: \(error.localizedDescription, privacy: .public)")
            state = .idle
            removeTap()
            notifyFailure(error)
        }
    }

    func stop() {
        guard state == .running || state == .starting else {
            return
        }

        state = .stopping
        removeTap()
        engine.stop()
        engine.reset()
        state = .idle
        notifyStop()
    }

    private func configureSession() throws {
        #if !os(macOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
        try session.setPreferredSampleRate(targetFormat.sampleRate)
        try session.setPreferredIOBufferDuration(Double(bufferSize) / targetFormat.sampleRate)
        try session.setActive(true)
        #endif
    }

    private func installTap(on node: AVAudioNode) {
        guard let inputFormat else {
            logger.error("Input format unavailable when installing tap")
            return
        }

        node.removeTap(onBus: 0)
        node.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, _ in
            self?.handleCapturedBuffer(buffer)
        }
    }

    private func removeTap() {
        engine.inputNode.removeTap(onBus: 0)
    }

    private func handleCapturedBuffer(_ buffer: AVAudioPCMBuffer) {
        guard state == .running else { return }
        guard buffer.frameLength > 0 else { return }

        queue.async { [weak self] in
            guard let self else { return }

            let convertedBuffer: AVAudioPCMBuffer
            if let converter = self.converter, let inputFormat = self.inputFormat {
                let ratio = self.targetFormat.sampleRate / inputFormat.sampleRate
                let capacity = max(1, AVAudioFrameCount(Double(buffer.frameCapacity) * ratio) + 1)
                guard let temp = AVAudioPCMBuffer(pcmFormat: self.targetFormat, frameCapacity: capacity) else {
                    self.logger.error("Failed to allocate buffer for conversion")
                    return
                }
                temp.frameLength = temp.frameCapacity

                var conversionError: NSError?
                let inputBlock: AVAudioConverterInputBlock = { _, status in
                    status.pointee = .haveData
                    return buffer
                }

                converter.convert(to: temp, error: &conversionError, withInputFrom: inputBlock)

                if let conversionError {
                    self.logger.error("Conversion error: \(conversionError.localizedDescription, privacy: .public)")
                    return
                }
                convertedBuffer = temp
            } else {
                convertedBuffer = buffer
            }

            guard let channelData = convertedBuffer.floatChannelData else { return }
            let frameLength = Int(convertedBuffer.frameLength)
            let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
            let peak = samples.max() ?? 0
            self.logger.debug("Chunk frames=\(frameLength) peak=\(String(format: "%.5f", peak), privacy: .public)")
            let chunk = AudioChunk(samples: samples, sampleRate: self.targetFormat.sampleRate)
            self.notifyChunk(chunk)
        }
    }

    private func notifyStart() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            delegate?.audioControllerDidStart(self)
        }
    }

    private func notifyChunk(_ chunk: AudioChunk) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            delegate?.audioController(self, didProduce: chunk)
        }
    }

    private func notifyStop() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            delegate?.audioControllerDidStop(self)
        }
    }

    private func notifyFailure(_ error: Error) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            delegate?.audioController(self, didFailWith: error)
        }
    }
}
