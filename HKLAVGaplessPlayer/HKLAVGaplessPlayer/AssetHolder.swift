//
//  AssetHolder.swift
//  SimpleGaplessPlayer
//
//  Created by Hirohito Kato on 2015/01/20.
//  Copyright (c) 2015年 Hirohito Kato. All rights reserved.
//

import Foundation
import AVFoundation

/**
* アセット配列に格納するデータ構造。AVAsset.durationなどのvalueにアクセスするのは
* 毎回ロックが入るなどして高コストであるため(iOS8.1.2時点)、値をアセットと共にキャッシュするのが目的
*/
class AssetHolder {
    /// 外部から渡されたアセット
    let asset: AVAsset
    /// アセットの再生時間。キャッシュした値があればそれを返す
    var duration: CMTime {
        get {
            if _duration != nil {
                return _duration
            } else {
                _duration = asset.duration
                return _duration
            }
        }
        set { _duration = newValue }
    }
    init(_ asset: AVAsset, completionHandler: (CMTime) -> Void) {
        self.asset = asset
        // AssetReaderFragmentのビルドに必要な情報を非同期に読み込み始めておく
        // （もしビルドまでに間に合わなかった場合でも、処理がブロックされる
        //   時間を短くできることを狙っている）
        let keys = ["duration","tracks", "preferredTransform", "readable"]
        asset.loadValuesAsynchronouslyForKeys(keys) {
            self.duration = asset.duration
            completionHandler(self.duration)
        }
    }
    private var _duration: CMTime! = nil
}
