//
//  AudioChunk.swift
//  Starling
//
//  Created by Ryan D'Onofrio on 10/11/25.
//

import Foundation

struct AudioChunk {
    let samples: [Float]
    let sampleRate: Double

    var frameCount: Int {
        samples.count
    }

    var duration: TimeInterval {
        guard frameCount > 0 else { return 0 }
        return Double(frameCount) / sampleRate
    }

    func pcm16LittleEndian() -> Data {
        guard !samples.isEmpty else { return Data() }

        var pcmData = Data(capacity: samples.count * MemoryLayout<Int16>.size)
        for sample in samples {
            let clipped = max(-1.0, min(1.0, Double(sample)))
            var intSample = Int16(clipped * Double(Int16.max))
            withUnsafeBytes(of: &intSample) { buffer in
                pcmData.append(buffer.bindMemory(to: UInt8.self))
            }
        }

        return pcmData
    }
}
