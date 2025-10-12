//
//  AudioCaptureController.swift
//  Starling
//
//  Created by Ryan D'Onofrio on 10/11/25.
//

import AVFoundation
import AudioToolbox
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

    enum CaptureError: Swift.Error {
        case invalidAudioFormat
    }

    enum DeviceError: Swift.Error {
        case deviceNotFound
        case propertySetFailed(OSStatus)
    }

    private let configuration: AudioCaptureConfiguration
    private let engine = AVAudioEngine()
    private let targetFormat: AVAudioFormat
    private let logger = Logger(subsystem: "com.starling.app", category: "AudioCapture")
    private let queue = DispatchQueue(label: "com.starling.audio-capture", qos: .userInitiated)
    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?
    private var pendingDeviceUID: String?
    private var currentDeviceID: AudioDeviceID?

    weak var delegate: AudioCaptureControllerDelegate?

    private(set) var state: State = .idle

    init(configuration: AudioCaptureConfiguration = .default) throws {
        self.configuration = configuration
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: configuration.sampleRate,
            channels: configuration.channelCount,
            interleaved: false
        ) else {
            throw CaptureError.invalidAudioFormat
        }
        targetFormat = format
    }

    func start() {
        guard state == .idle else {
            logger.debug("Ignored start request in state \(String(describing: self.state), privacy: .public)")
            return
        }

        state = .starting

        do {
            try applyInputDeviceIfNeeded()
        } catch {
            logger.error("Failed to apply input device: \(String(describing: error), privacy: .public)")
        }

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
        if audioUnit.maximumFramesToRender < configuration.bufferSize {
            audioUnit.maximumFramesToRender = configuration.bufferSize
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

    func setInputDevice(uid: String?) throws {
        pendingDeviceUID = uid
        if state == .idle {
            do {
                try applyInputDeviceIfNeeded()
                logger.log("Microphone selection updated to \(uid ?? "System Default", privacy: .public)")
            } catch {
                logger.error("Failed to set microphone: \(String(describing: error), privacy: .public)")
                throw error
            }
        } else {
            logger.debug("Microphone change queued until capture returns to idle")
        }
    }

    private func configureSession() throws {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        guard status == .authorized else {
            logger.error("Microphone permission not granted (status: \(String(describing: status), privacy: .public))")
            throw NSError(domain: "AudioCapture", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Microphone access required"
            ])
        }
        #if !os(macOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
        try session.setPreferredSampleRate(configuration.sampleRate)
        try session.setPreferredIOBufferDuration(Double(configuration.bufferSize) / configuration.sampleRate)
        try session.setActive(true)
        #endif
    }

    private func installTap(on node: AVAudioNode) {
        guard let inputFormat else {
            logger.error("Input format unavailable when installing tap")
            return
        }

        node.removeTap(onBus: 0)
        node.installTap(onBus: 0, bufferSize: configuration.bufferSize, format: inputFormat) { [weak self] buffer, _ in
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

    private func applyInputDeviceIfNeeded() throws {
        guard let audioUnit = engine.inputNode.audioUnit else {
            throw DeviceError.propertySetFailed(-1)
        }

        if let uid = pendingDeviceUID {
            let deviceID = try Self.deviceID(forUID: uid)
            if currentDeviceID == deviceID { return }
            var mutableID = deviceID
            let status = AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &mutableID,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
            guard status == noErr else {
                throw DeviceError.propertySetFailed(status)
            }
            currentDeviceID = deviceID
        } else {
            guard currentDeviceID != nil else { return }
            var defaultDevice = AudioDeviceID(kAudioObjectUnknown)
            let status = AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &defaultDevice,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
            guard status == noErr else {
                throw DeviceError.propertySetFailed(status)
            }
            currentDeviceID = nil
        }
    }

    private static func deviceID(forUID uid: String) throws -> AudioDeviceID {
        var uidCF = uid as CFString
        var deviceID = AudioDeviceID()

        let status: OSStatus = withUnsafeMutablePointer(to: &uidCF) { uidPointer in
            withUnsafeMutablePointer(to: &deviceID) { devicePointer in
                var translation = AudioValueTranslation(
                    mInputData: UnsafeMutableRawPointer(uidPointer),
                    mInputDataSize: UInt32(MemoryLayout<CFString>.size),
                    mOutputData: UnsafeMutableRawPointer(devicePointer),
                    mOutputDataSize: UInt32(MemoryLayout<AudioDeviceID>.size)
                )

                var propertyAddress = AudioObjectPropertyAddress(
                    mSelector: kAudioHardwarePropertyDeviceForUID,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain
                )

                var size = UInt32(MemoryLayout<AudioValueTranslation>.size)
                return AudioObjectGetPropertyData(
                    AudioObjectID(kAudioObjectSystemObject),
                    &propertyAddress,
                    0,
                    nil,
                    &size,
                    &translation
                )
            }
        }

        guard status == noErr else {
            throw DeviceError.deviceNotFound
        }

        return deviceID
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
