//
//  HKLAVFoundationUtils.swift
//  SimpleGaplessPlayer
//
//  Created by Hirohito Kato on 2014/12/23.
//  Copyright (c) 2014年 Hirohito Kato. All rights reserved.
//

import Foundation
import AVFoundation

extension AVURLAsset: Printable, DebugPrintable {
    public override var description: String {
        var str: String = ""
        str += "---------------------\n"
        str += "<file : \(URL.lastPathComponent!)>\n"
        str += "[Availability]\n"
        str += " playable              : \(playable)\n"
        str += " exportable            : \(exportable)\n"
        str += " readable              : \(readable)\n"
        str += " composable            : \(composable)\n"
        str += " hasProtectedContent   : \(hasProtectedContent)\n"
        str += " compatibleWithSavedPhotosAlbum: \(compatibleWithSavedPhotosAlbum)\n"
        str += "[Asset Information]\n"
        str += " creationDate          : \(creationDate)\n"
        str += " duration              : \(duration.description)\n"
        str += " lyrics                : \(lyrics)\n"
        str += " preferredRate         : \(preferredRate)\n"
        str += " preferredVolume       : \(preferredVolume)\n"
        str += " preferredTransform    : \(preferredTransform.description)\n"
        str += " referenceRestrictions : \(referenceRestrictions.description)\n"
        str += "[Track Information] (\(tracks.count) tracks)\n"
        for (i, track) in enumerate(tracks) {
            str += "\(track.description)\n"
        }
        str += " trackGroups:\(trackGroups)\n"
        str += "[Metadata]\n"
        str += " commonMetadata: \(commonMetadata.count)\n"
        for (i, md) in enumerate(commonMetadata) {
            str += "  | \(md.description),\n"
        }
        str += " metadata: \(metadata.count)\n"
        for (i, md) in enumerate(metadata) {
            str += "  | \(md.description),\n"
        }
        str += " availableMetadataFormats : \(availableMetadataFormats)\n"

        str += " availableChapterLocales  : \(availableChapterLocales)\n"
        str += " availableMediaCharacteristicsWithMediaSelectionOptions: \(availableMediaCharacteristicsWithMediaSelectionOptions)\n"
        str += "---------------------"
        return str
    }
    public override var debugDescription: String {
        return description
    }
}

extension AVAssetReferenceRestrictions : Printable, DebugPrintable {
    public var description: String {
        switch self.rawValue {
        case 0:
            return "RestrictionForbidNone"
        case 1:
            return "RestrictionForbidRemoteReferenceToLocal"
        case 2:
            return "RestrictionForbidLocalReferenceToRemote"
        case 3:
            return "RestrictionForbidCrossSiteReference"
        case 4:
            return "RestrictionForbidLocalReferenceToLocal"
        case 5:
            return "RestrictionForbidAll"
        default:
            return "Unknown value(\(self.rawValue))"
        }
    }
    public var debugDescription: String {
        return description
    }
}

extension AVAssetTrack: Printable, DebugPrintable {
    public override var description: String {
        var str = ""
        str += " [track #\(trackID)]\n"
        str += "  | mediaType              : \(mediaTypeString(mediaType))\n"
        str += "  | playable               : \(playable)\n"
        str += "  | enabled                : \(enabled)\n"
        str += "  | selfContained          : \(selfContained)\n"
        str += "  | totalSampleDataLength  : \(totalSampleDataLength)\n"
        str += "  | timeRange              : \(timeRange.description)\n"
        str += "  | naturalTimeScale       : \(naturalTimeScale)\n"
        str += "  | estimatedDataRate      : \(estimatedDataRate/1_000_000) Mbps\n"
        str += "  | naturalSize            : {\(naturalSize.width), \(naturalSize.height)}\n"
        str += "  | preferredTransform     : \(preferredTransform.description)\n"
        str += "  | nominalFrameRate       : \(nominalFrameRate)\n"
        str += "  | minFrameDuration       : \(minFrameDuration.description)\n"
        str += "  | requiresFrameReordering: \(requiresFrameReordering)\n"
        str += "  | availableTrackAssociationTypes: \(availableTrackAssociationTypes)\n"
        str += "  | segments               : \(segments.count)\n"
        for (i, segment) in enumerate(segments) {
            str += "  |  | \(segment.description)"
        }
        return str
    }
    public override var debugDescription: String {
        return description
    }
    func mediaTypeString(type:String)-> String {
        switch type {
        case AVMediaTypeVideo: return "video"
        case AVMediaTypeAudio: return "audio"
        case AVMediaTypeText: return "text"
        case AVMediaTypeClosedCaption: return "closed caption"
        case AVMediaTypeSubtitle: return "subtitle"
        case AVMediaTypeTimecode: return "timecode"
        case AVMediaTypeMetadata: return "metadata"
        case AVMediaTypeMuxed: return "muxed"
        default:
            return "Unknown"
        }
    }
}

extension AVMetadataItem: Printable, DebugPrintable {
    public override var description: String {
        var str = "[\(key)"
        if self.dateValue != nil {
            str += "(date) : \(self.dateValue)]"
        } else if self.stringValue != nil {
            str += "(str) : \(self.stringValue)]"
        } else if self.numberValue != nil {
            str += "(num) : \(self.numberValue)]"
        }
        return str
    }
    public override var debugDescription: String {
        var str = ""
        str += "  | key             : \(key)\n"
        str += "  | keySpace        : \(keySpace)\n"
        str += "  | identifier      : \(identifier)\n"
        if dataType != nil {
            str += "  | dataType    : \(dataType)\n"
        }
        if (time.flags & .Valid).rawValue > 0 {
            str += "  | time        : \(time.description)\n"
        }
        if self.dateValue != nil {
            str += "  | value(date) : \(self.dateValue)\n"
        } else if self.stringValue != nil {
            str += "  | value(str)  : \(self.stringValue)\n"
        } else if self.numberValue != nil {
            str += "  | value(num)  : \(self.numberValue)\n"
        }
        str += "  | extraAttributes : \(extraAttributes)\n"
        return str
    }
}

extension AVAssetTrackSegment: Printable, DebugPrintable {
    public override var description: String {
        return "{ empty:\(empty), timeMapping:\(timeMapping.description)}"
    }
    public override var debugDescription: String {
        return description
    }
}
