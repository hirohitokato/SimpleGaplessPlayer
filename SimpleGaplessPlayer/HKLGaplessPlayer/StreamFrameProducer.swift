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

    /// 格納しているアセットの合計再生時間を返す
    var amountDuration: CMTime {
        let lock = ScopedLock(self)
        return _amountDuration
    }

    /// アセット全体のうち再生対象となる時間。ウィンドウ時間
    var maxDuration = CMTime(value: 30, 1)

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
            _currentPresentationTimestamp = CMSampleBufferGetPresentationTimeStamp(nextBuffer)

            return (nextBuffer, CMSampleBufferGetDuration(nextBuffer))
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

    private var _currentPosition: Float = 0.0
    private var _currentPresentationTimestamp: CMTime = kCMTimeZero

    /// アセット全体の総再生時間（内部管理用）
    private var _amountDuration = kCMTimeZero

    // 現在のリーダーが指すアセットの位置を返す
    private var _current: (index: Int, asset: AVAsset)! {
        if let reader = _readers.first {
            for (i, asset) in enumerate(self._assets) {
                if reader.asset === asset {
                    return (i, asset)
                }
            }
        }
        return nil
    }

    /**
    指定した位置(0.0-1.0)に対するAVPlayerのインデックスと、その時刻を計算して返す

    :param: position 一連のムービーにおける位置

    :returns: アセット列におけるインデックスとシーク位置のタプル
    */
    private func playerInfoForPosition(position: Float) -> (index:Int, time:CMTime)? {
        let lock = ScopedLock(self)

        if _assets.isEmpty { return nil }

        // 指定したポジションを、時間での表現に変換する
        var expectedOffset = maxDuration * position

        let positionAt = { (targets:[AVAsset], offset:CMTime, reverseOrder: Bool)
            -> (Int, CMTime)? in

            var offset = offset
            let targets = reverseOrder ? reverse(targets) : targets
            for (i, asset) in enumerate(targets) {
                let duration = asset.duration

                if offset <= duration {
                    let time = reverseOrder ? duration - offset : offset
                    return (i, time)
                }
                offset -= duration
            }
            return nil
        }

        // 1) 0.0の位置を算出する
        var indexAtZero: Int
        var timeAtZero: CMTime

        if _amountDuration <= maxDuration {
            // アセットの総時間が最大時間よりも少ないため、先頭が起点になる
            (indexAtZero, timeAtZero) = (0, kCMTimeZero)
        } else {
            if let current = _current {
                let targets = reverse(_assets[0...current.index])
                // 現在の再生場所を起点にrate=0.0地点を探索するが、
                // ループの中で先頭だけを特別視するのを避けるため(すべてdurationで計算したい)、
                // ここでゲタを履かせておく
                let initialOffsetTime = current.asset.duration - _currentPresentationTimestamp
                var offset = maxDuration * _currentPosition + initialOffsetTime

                if let resultAtZero = positionAt(targets, offset, true) {
                    (indexAtZero, timeAtZero) = resultAtZero
                    expectedOffset += timeAtZero
                } else {
                    return nil
                }
            } else {
                return nil
            }
        }

        // 2) 算出した0.0位置からexpectedOffsetを足した場所を調べて返す
        let targets = Array(_assets[indexAtZero..<_assets.endIndex])
        
        return positionAt(targets, expectedOffset, false)
    }

    /**
    サンプルバッファの生成
    */
    private func _prepareNextBuffer() -> CMSampleBufferRef? {

        // サンプルバッファを生成する
        while let target = _readers.first {

            switch target.status {
            case .Reading:
                // サンプルバッファの読み込み
                let out = target.output
                if let sbuf = out.copyNextSampleBuffer() {

                    // 取得したサンプルバッファの情報で更新
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

        // 読み込み済みリーダーの数が上限になっていれば何もしない
        if (_readers.count >= kMaximumNumOfReaders) {
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