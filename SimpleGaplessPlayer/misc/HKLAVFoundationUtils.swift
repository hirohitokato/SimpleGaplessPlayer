//
//  HKLAVFoundationUtils.swift
//  SimpleGaplessPlayer
//
//  Created by Hirohito Kato on 2014/12/23.
//  Copyright (c) 2014年 Hirohito Kato. All rights reserved.
//

import Foundation
import AVFoundation

extension AVAssetTrack: Printable, DebugPrintable {
    override public var debugDescription: String {
        var str = "AVAssetTrack\n"
        str += "| trackID           : \(self.trackID)\n"
        str += "| mediaType         : \(self.mediaType)\n"
        str += "| playable          : \(playable)\n"
        str += "| enabled           : \(enabled)\n"
        str += "| selfContained     : \(selfContained)\n"
        str += "| totalSampleDataLength:\(totalSampleDataLength)\n"
        str += "| timeRange         : \(timeRange.start.value)/\(timeRange.start.timescale),\(timeRange.duration.value)/\(timeRange.duration.timescale)\n"
        str += "| estimatedDataRate : \(estimatedDataRate/1_000_000) Mbps\n"
        str += "| naturalTimeScale  : \(naturalTimeScale)\n"
        str += "| naturalSize       : \(naturalSize)\n"
        str += "| preferredTransform: \(preferredTransform)\n"
        str += "| preferredVolume   : \(preferredVolume)\n"
        str += "| nominalFrameRate  : \(nominalFrameRate)\n"
        str += "| minFrameDuration  : \(minFrameDuration)\n"
        return str
    }

    override public var description: String {
        return debugDescription
    }
}
