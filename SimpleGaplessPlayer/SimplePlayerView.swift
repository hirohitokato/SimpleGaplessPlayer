//
//  SimplePlayerView.swift
//  LearningVideoComposition
//
//  Created by Hirohito Kato on 2014/12/17.
//  Copyright (c) 2014年 Hirohito Kato. All rights reserved.
//

import UIKit
import AVFoundation

class SimplePlayerView: UIView {
    override class func layerClass() -> AnyClass {
        return AVPlayerLayer.self
    }
    var player: AVPlayer! {
        get {
            let playerLayer = self.layer as? AVPlayerLayer
            return playerLayer?.player
        }
        set(newPlayer) {
            let playerLayer = self.layer as? AVPlayerLayer
            playerLayer?.player = newPlayer
        }
    }
}