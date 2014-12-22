//
//  StreamFrameProducer.swift
//
//  Created by Hirohito Kato on 2014/12/22.
//  Copyright (c) 2014年 Hirohito Kato. All rights reserved.
//

import Foundation
import CoreMedia
import AVFoundation

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

            if self._readers.count < 5 {
                if let assetreader = AssetReaderFragment(asset: asset) {
                    self._readers.append(assetreader)
                    assetreader.startReading()
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
        if let nextBuffer = self.prepareNextBuffer() {
            return (nextBuffer, _frameInterval)
        }
        return nil
    }

    // MARK: Privates

    private var _assets = [AVAsset]() // アセット
    private var _readers = [AssetReaderFragment]()
    private let _requestSignal = dispatch_semaphore_create(0) // アセットリーダー生成時の排他処理

    private let _kMaximumNumOfReaders = 3 // AVAssetReaderで事前にstartReading()しておくムービーの数

    /// 現在のアセットにおけるフレーム表示期間
    private var _frameInterval: CMTime = kCMTimeZero

    /// 内部管理用の総時間
    private var _amountDuration = kCMTimeZero

    /**
    サンプルバッファの生成
    */
    private func prepareNextBuffer() -> CMSampleBufferRef? {
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
                    _asyncPrepareNextAssetReader()
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

    private func _asyncPrepareNextAssetReader() {
        let lock = ScopedLock(self)

        // 読み込み済みリーダーの数が上限になっていれば何もしない
        if (_readers.count > _kMaximumNumOfReaders) {
            return
        }
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
            [unowned self] in

            let lock = ScopedLock(self)

            // もしまだ読み込みしていないアセットがあれば読み込む
            for (i, asset) in enumerate(self._assets) {
                if self._readers.last?.asset === asset && i+1 < self._assets.count {

                    if let assetreader = AssetReaderFragment(asset: self._assets[i+1]) {
                        self._readers.append(assetreader)
                        assetreader.startReading()
                    } else {
                        NSLog("Failed to instantiate a AssetReaderFragment.")
                    }
                    
                    break
                }
            }
        }
    }
    
}
