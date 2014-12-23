//
//  StreamFrameProducer.swift
//
//  Created by Hirohito Kato on 2014/12/22.
//  Copyright (c) 2014年 Hirohito Kato. All rights reserved.
//

import Foundation
import CoreMedia
import AVFoundation

let kMaximumNumOfReaders = 3 // AVAssetReaderで事前にstartReading()しておくムービーの数

/**
:class: StreamFrameProducer
:abstract:
アセットおよびそのアセットリーダーを保持していて、外部からのリクエストにより
非同期でサンプルバッファを生成する
*/
internal class StreamFrameProducer: NSObject {

    /// 格納しているアセットの合計再生時間
    var amountDuration: CMTime {
        let lock = ScopedLock(self)
        return _amountDuration
    }

    /**
    アセットを内部キューの末尾に保存する。余裕がある場合はアセットリーダーも
    同時に生成する

    :param: asset フレームの取り出し対象となるアセット
    */
    func appendAsset(asset: AVAsset) {
        asset.loadValuesAsynchronouslyForKeys(["duration"]) { [unowned self] in
            let lock = ScopedLock(self)

            self._assets.append(asset)
            self._amountDuration += asset.duration

            // 読み込んだリーダーの数に応じて、追加でリーダーを作成する
            if self._readers.count < kMaximumNumOfReaders {
                if let assetreader = AssetReaderFragment(asset:asset) {
                    self._readers.append(assetreader)
                } else {
                    NSLog("Failed to instantiate a AssetReaderFragment.")
                }
            }
            
        }
    }

    /**
    生成された最新のサンプルバッファを返す。読み込まれた後、サンプルバッファは
    次に読み込まれるまでnilに

    :returns: リーダーから読み込まれたサンプルバッファ
    */
    func nextSampleBuffer() -> (CMSampleBufferRef, CMTime)! {
        let lock = ScopedLock(self)

        // 一度取得したらnilに変わる
        if let nextBuffer = self._prepareNextBuffer() {
            return (nextBuffer, _frameInterval)
        }
        return nil
    }

    func startReading() -> Bool {
        let lock = ScopedLock(self)
        if _assets.isEmpty {
            return false
        }
        _prepareNextAssetReader()
        return true
    }

    /**
    読み込み前のリーダーをすべて削除し、読み込みをキャンセルする。

    内部で保持しているAVAssetReaderOutputをすべて削除し、読み込み処理を
    停止する。再び読み込めるようにする場合、startReading()を呼ぶか、別のアセットを
    appendAsset()して、リーダーの準備をしておくこと
    */
    func cancelReading() {
        let lock = ScopedLock(self)
        _readers.removeAll(keepCapacity: false)
    }

    // MARK: Privates

    private var _assets = [AVAsset]() // アセット
    private var _readers = [AssetReaderFragment]()

    /// 現在のアセットにおけるフレーム表示期間
    private var _frameInterval: CMTime = kCMTimeZero

    /// 内部管理用の総時間
    private var _amountDuration = kCMTimeZero

    /**
    サンプルバッファの生成
    */
    private func _prepareNextBuffer() -> CMSampleBufferRef? {
        _frameInterval = kCMTimeIndefinite

        // サンプルバッファを生成する
        while !_readers.isEmpty {

            let target = _readers.first!

            switch target.status {
            case .Reading:
                // サンプルバッファの読み込み
                let out = target.output
                if let sbuf = out.copyNextSampleBuffer() {

                    // 取得したサンプルバッファの情報で更新
                    _frameInterval = target.frameInterval
                    return sbuf

                } else {
                    println("move to next")
                    // 次のムービーへ移動
                    _readers.removeAtIndex(0)
                    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0)) {
                        [unowned self] in
                        self._prepareNextAssetReader()
                    }
                }
            case .Completed:
                // AVAssetReaderは.Reading状態でcopyNextSampleBufferを返した
                // 次のタイミングで.Completedに遷移するため、ここには来ないはず
                _readers.removeAtIndex(0)
            default:
                assert(false, "Invalid state\(Int(target.status.rawValue)). Something is wrong.")
                _readers.removeAtIndex(0)
            }
        }
        return nil
    }

    private func _prepareNextAssetReader() {
        let lock = ScopedLock(self)

        // 読み込み済みリーダーの数が上限になっているか、読み込むアセットが
        // なければ何もしない
        if (_readers.count >= kMaximumNumOfReaders && _assets.count == 0) {
            return
        }

        // 読み込みしていないアセットがあれば読み込む
        outer: for (i, asset) in enumerate(self._assets) {

            // 登録済みの最後のアセットを見つけて、それ以降のアセットを
            // 追加対象として読み込む
            if _readers.last?.asset === asset && i+1 < _assets.count {
                for target_asset in _assets[i+1..<_assets.count] {

                    if let assetreader = AssetReaderFragment(asset:target_asset) {
                        _readers.append(assetreader)
                    } else {
                        NSLog("Failed to instantiate a AssetReaderFragment.")
                        break outer
                    }

                    // 読み込み済みリーダーの数が上限になれば処理終了
                    if (_readers.count >= kMaximumNumOfReaders) {
                        break outer
                    }
                }

            }

        }
    }
}
