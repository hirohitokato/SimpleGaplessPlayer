//
//  HKLAVFoundationUtils.swift
//  SimpleGaplessPlayer
//
//  Created by Hirohito Kato on 2014/12/23.
//  Copyright (c) 2014年 Hirohito Kato. All rights reserved.
//

import Foundation
import AVFoundation

extension AVURLAsset {
    open override var description: String {
        var str: String = ""
        str += "---------------------\n"
        str += "<file : \(url.lastPathComponent)>\n"
        str += "[Availability]\n"
        str += " isPlayable            : \(isPlayable)\n"
        str += " isExportable          : \(isExportable)\n"
        str += " isReadable            : \(isReadable)\n"
        str += " isComposable          : \(isComposable)\n"
        str += " hasProtectedContent   : \(hasProtectedContent)\n"
        str += " isCompatibleWithSavedPhotosAlbum: \(isCompatibleWithSavedPhotosAlbum)\n"
        str += "[Asset Information]\n"
        str += " creationDate          : \(String(describing: creationDate))\n"
        str += " duration              : \(duration.description)\n"
        str += " lyrics                : \(String(describing: lyrics))\n"
        str += " preferredRate         : \(preferredRate)\n"
        str += " preferredVolume       : \(preferredVolume)\n"
        str += " preferredTransform    : \(preferredTransform.description)\n"
        str += " referenceRestrictions : \(referenceRestrictions.description)\n"
        str += "[Track Information] (\(tracks.count) tracks)\n"
        for (_, track) in tracks.enumerated() {
            str += "\(track.description)\n"
        }
        str += " trackGroups:\(trackGroups)\n"
        str += "[Metadata]\n"
        str += " commonMetadata: \(commonMetadata.count)\n"
        for (_, md) in commonMetadata.enumerated() {
            str += "  | \(md.description),\n"
        }
        str += " metadata: \(metadata.count)\n"
        for (_, md) in metadata.enumerated() {
            str += "  | \(md.description),\n"
        }
        str += " availableMetadataFormats : \(availableMetadataFormats)\n"

        str += " availableChapterLocales  : \(availableChapterLocales)\n"
        str += " availableMediaCharacteristicsWithMediaSelectionOptions: \(availableMediaCharacteristicsWithMediaSelectionOptions)\n"
        str += "---------------------"
        return str
    }
    open override var debugDescription: String {
        return description
    }
}

extension AVAssetReferenceRestrictions : CustomStringConvertible, CustomDebugStringConvertible {
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

extension AVAssetTrack {
    open override var description: String {
        var str = ""
        str += " [track #\(trackID)]\n"
        str += "  | mediaType              : \(media(type: mediaType))\n"
        str += "  | isPlayable             : \(isPlayable)\n"
        str += "  | isEnabled              : \(isEnabled)\n"
        str += "  | selfContained          : \(isSelfContained)\n"
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
        for (_, segment) in segments.enumerated() {
            str += "  |  | \(segment.description)"
        }
        return str
    }
    open override var debugDescription: String {
        return description
    }
    func media(type: AVMediaType)-> String {
        switch type {
        case .video: return "video"
        case .audio: return "audio"
        case .text: return "text"
        case .closedCaption: return "closed caption"
        case .subtitle: return "subtitle"
        case .timecode: return "timecode"
        case .metadata: return "metadata"
        case .muxed: return "muxed"
        default:
            return "Unknown"
        }
    }
}

extension AVMetadataItem {
    open override var description: String {
        var str = "[\(String(describing: key))"
        if self.dateValue != nil {
            str += "(date) : \(String(describing: self.dateValue))]"
        } else if self.stringValue != nil {
            str += "(str) : \(String(describing: self.stringValue))]"
        } else if self.numberValue != nil {
            str += "(num) : \(String(describing: self.numberValue))]"
        }
        return str
    }
    open override var debugDescription: String {
        var str = ""
        str += "  | key             : \(String(describing: key))\n"
        str += "  | keySpace        : \(String(describing: keySpace))\n"
        str += "  | identifier      : \(String(describing: identifier))\n"
        if dataType != nil {
            str += "  | dataType    : \(String(describing: dataType))\n"
        }
        if time.flags.contains(.valid) {
            str += "  | time        : \(time.description)\n"
        }
        if self.dateValue != nil {
            str += "  | value(date) : \(String(describing: self.dateValue))\n"
        } else if self.stringValue != nil {
            str += "  | value(str)  : \(String(describing: self.stringValue))\n"
        } else if self.numberValue != nil {
            str += "  | value(num)  : \(String(describing: self.numberValue))\n"
        }
        str += "  | extraAttributes : \(String(describing: extraAttributes))\n"
        return str
    }
}

extension AVAssetTrackSegment {
    open override var description: String {
        return "{ empty:\(isEmpty), timeMapping:\(timeMapping.description)}"
    }
    open override var debugDescription: String {
        return description
    }
}
