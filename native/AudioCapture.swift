import AVFoundation
import Foundation
import ScreenCaptureKit

@available(macOS 14.0, *)
class AudioCaptureDelegate: NSObject, SCStreamDelegate, SCStreamOutput {
    private var isRunning = true
    private let sampleRate: Double = 16000.0
    private var resampler: AVAudioConverter?
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, isRunning else { return }
        
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
        guard let audioStreamBasicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else { return }
        
        let sourceFormat = AVAudioFormat(streamDescription: audioStreamBasicDescription)
        guard let sourceFormat = sourceFormat else { return }
        
        let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: 1, interleaved: true)
        guard let targetFormat = targetFormat else { return }
        
        if resampler == nil {
            resampler = AVAudioConverter(from: sourceFormat, to: targetFormat)
        }
        
        guard let audioBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        
        var lengthAtOffset: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        CMBlockBufferGetDataPointer(audioBuffer, atOffset: 0, lengthAtOffsetOut: &lengthAtOffset, totalLengthOut: nil, dataPointerOut: &dataPointer)
        
        guard let dataPointer = dataPointer else { return }
        
        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: AVAudioFrameCount(frameCount)) else { return }
        pcmBuffer.frameLength = AVAudioFrameCount(frameCount)
        
        let bytesPerFrame = Int(sourceFormat.streamDescription.pointee.mBytesPerFrame)
        let totalBytes = frameCount * bytesPerFrame
        
        if let channelData = pcmBuffer.floatChannelData {
            memcpy(channelData[0], dataPointer, totalBytes)
        } else if let channelData = pcmBuffer.int16ChannelData {
            memcpy(channelData[0], dataPointer, totalBytes)
        } else if let channelData = pcmBuffer.int32ChannelData {
            memcpy(channelData[0], dataPointer, totalBytes)
        }
        
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: AVAudioFrameCount(Double(frameCount) * (sampleRate / sourceFormat.sampleRate) + 1.0)) else { return }
        
        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return pcmBuffer
        }
        
        resampler?.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
        
        if let error = error {
            fputs("Conversion error: \(error.localizedDescription)\n", stderr)
            return
        }
        
        guard let channelData = outputBuffer.int16ChannelData else { return }
        let frameLength = Int(outputBuffer.frameLength)
        let data = Data(bytes: channelData[0], count: frameLength * MemoryLayout<Int16>.size)
        
        FileHandle.standardOutput.write(data)
    }
    
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        fputs("Stream stopped with error: \(error.localizedDescription)\n", stderr)
        isRunning = false
    }
    
    func stop() {
        isRunning = false
    }
}

@available(macOS 14.0, *)
func captureSystemAudio() async throws {
    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
    
    guard let display = content.displays.first else {
        throw NSError(domain: "AudioCapture", code: 1, userInfo: [NSLocalizedDescriptionKey: "No display found"])
    }
    
    let filter = SCContentFilter(display: display, excludingWindows: [])
    
    let config = SCStreamConfiguration()
    config.capturesAudio = true
    config.sampleRate = 48000
    config.channelCount = 2
    config.excludesCurrentProcessAudio = true
    config.width = 1
    config.height = 1
    config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
    
    let delegate = AudioCaptureDelegate()
    let stream = SCStream(filter: filter, configuration: config, delegate: delegate)
    
    try stream.addStreamOutput(delegate, type: .audio, sampleHandlerQueue: DispatchQueue(label: "audio.capture.queue"))
    
    try await stream.startCapture()
    
    fputs("System audio capture started (16kHz mono PCM to stdout)\n", stderr)
    fputs("Press Ctrl+C to stop\n", stderr)
    
    dispatchMain()
}

if #available(macOS 14.0, *) {
    Task {
        do {
            try await captureSystemAudio()
        } catch {
            fputs("Error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
    RunLoop.main.run()
} else {
    fputs("Error: macOS 14.0 or later required for ScreenCaptureKit\n", stderr)
    exit(1)
}
