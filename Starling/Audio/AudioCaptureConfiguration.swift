//
//  AudioCaptureConfiguration.swift
//  Starling
//
//  Created by ChatGPT on 11/24/23.
//

import AVFoundation

struct AudioCaptureConfiguration {
    let sampleRate: Double
    let channelCount: AVAudioChannelCount
    let bufferSize: AVAudioFrameCount

    static let `default` = AudioCaptureConfiguration(
        sampleRate: 16_000,
        channelCount: 1,
        bufferSize: 1_024
    )
}
