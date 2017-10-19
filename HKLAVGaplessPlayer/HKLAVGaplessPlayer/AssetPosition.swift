//
//  AssetPosition.swift
//  SimpleGaplessPlayer
//
//  Created by Hirohito Kato on 2015/01/20.
//  Copyright (c) 2015年 Hirohito Kato. All rights reserved.
//

import Foundation
import AVFoundation

/**
*  アセット配列の中における位置（アセット位置）を表現するデータ構造
*/
struct AssetPosition: CustomStringConvertible, CustomDebugStringConvertible {
    var index: Int
    var time: CMTime
    init(_ index: Int, _ time: CMTime) {
        self.index=index
        self.time=time
    }
    var description: String {
        return "{i:\(self.index) t:\(self.time)}"
    }
    var debugDescription: String { return self.description }
}
