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
public class StreamFrameProducer: NSObject {

    /// 格納しているアセットの合計再生時間を返す
    var amountDuration: CMTime {
        let lock = ScopedLock(self)
        return _amountDuration
    }

    /// アセット全体のうち再生対象となる時間。時間窓に相当
    var window = CMTime(value: 30, 1)

    /// 再生レート。1.0が通常再生、2.0だと倍速再生
    var playbackRate: Float {
        return _playbackRate
    }

    /**
    アセットを内部キューの末尾に保存する。余裕がある場合はアセットリーダーも
    同時に生成する

    :param: asset フレームの取り出し対象となるアセット
    */
    func appendAsset(asset: AVAsset) {
        asset.loadValuesAsynchronouslyForKeys(["duration"]) {
            [unowned self] in
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
    再生対象のアセットを１つ進める。存在しない場合は何もしない
    */
    func advanceToNextAsset() {
        if !_readers.isEmpty {
            _readers.removeAtIndex(0)
            if !_readers.isEmpty {
                _prepareNextAssetReader()
            }
        }
    }

    /**
    生成された最新のサンプルバッファを返す。読み込まれた後、サンプルバッファは
    次に読み込まれるまでnilに

    :returns: リーダーから読み込まれたサンプルバッファ
    */
    func nextSampleBuffer() -> (sbuf:CMSampleBufferRef, presentationTimeStamp:CMTime, frameDuration:CMTime)! {
        let lock = ScopedLock(self)

        // 一度取得したらnilに変わる
        if let nextBuffer = self._prepareNextBuffer() {
            // 現在時刻を更新
            _currentPresentationTimestamp = nextBuffer.presentationTimeStamp
            return nextBuffer
        }
        return nil
    }

    /**
    アセットリーダーから読み込みを開始する

    :param: rate 再生レート
    :param: position 再生位置。Float.NaNの場合は現在位置を継続

    :returns: 読み込み開始に成功したかどうか
    */
    func startReading(rate:Float = 1.0, atPosition pos:Float? = nil) -> Bool {
        let lock = ScopedLock(self)
        if _assets.isEmpty {
            return false
        }
        var currentAsset: AVAsset? = nil
        if let pos = pos {
            if let playerInfo = _getAssetInfoForPosition(pos) {
                currentAsset = _assets[playerInfo.index]
                position = pos
                _currentPresentationTimestamp = playerInfo.timeStamp
            }
        } else {
            currentAsset = _readers.first?.asset
        }

        // レートが異なる場合、再生位置の指定があった場合は
        // リーダーを組み立て直してから再生準備を整える
        if rate != _playbackRate || pos != nil {
            println("cancelReading()")
            cancelReading()
        }
        _playbackRate = rate

        _prepareNextAssetReader(initial: currentAsset, atTime:_currentPresentationTimestamp)
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

    // MARK: Internals

    /// 再生位置。windowに対する先頭(古)〜末尾(新)を0.0-1.0の数値で表す
    dynamic var position: Float = 1.0

    // MARK: Privates

    private var _assets = [AVAsset]() // アセット
    private var _readers = [AssetReaderFragment]() // リーダー

    public var _currentPresentationTimestamp: CMTime = kCMTimeZero

    /// アセット全体の総再生時間（内部管理用）
    private var _amountDuration = kCMTimeZero

    /// 再生レート。1.0が通常再生、2.0だと倍速再生
    private var _playbackRate: Float = 0.0

    /**
    サンプルバッファの生成
    */
    private func _prepareNextBuffer()
        -> (sbuf:CMSampleBufferRef, presentationTimeStamp:CMTime, frameDuration:CMTime)?
    {

        // サンプルバッファを生成する
        while let target = _readers.first {

            switch target.status {
            case .Reading:
                // サンプルバッファの読み込み
                let out = target.output
                if let sbuf = out.copyNextSampleBuffer() {
                    // 取得したサンプルバッファの指す時間位置が1.0を超えていなければ、
                    // 表示用としてサンプルバッファを返す
                    let pts = CMSampleBufferGetPresentationTimeStamp(sbuf) + target.startTime
                    let pos = _getPosition(find(_assets, target.asset)!, time: pts)
                    if pos <= 1.0 + 0.02/*tolerance*/ {
                        return ( sbuf, pts, target.frameInterval )
                    }
                } else {
                    println("move to next")
                    // リーダーのサンプルバッファが枯渇した場合、または取得した
                    // サンプルバッファの位置が1.0を超えていた場合は、次のムービーへ移動する
                    _readers.removeAtIndex(0)
                    _currentPresentationTimestamp = kCMTimeZero
                    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0)) {
                        [unowned self] in
                        self._prepareNextAssetReader()
                    }
                }
            case .Completed:
                // AVAssetReaderは.Reading状態でcopyNextSampleBufferを返した
                // 次のタイミングで.Completedに遷移するため、ここには来ないはず
                _readers.removeAtIndex(0)
                _currentPresentationTimestamp = kCMTimeZero
            default:
                NSLog("Invalid state[\(Int(target.status.rawValue))]. Something is wrong.")
                _readers.removeAtIndex(0)
                _currentPresentationTimestamp = kCMTimeZero
            }
        }
        return nil
    }

    private func _prepareNextAssetReader(initial: AVAsset? = nil, atTime time: CMTime = kCMTimeZero) {
        let lock = ScopedLock(self)

        // 読み込み済みリーダーの数が上限になっていれば何もしない
        if (_readers.count >= kMaximumNumOfReaders) { return }

        // アセットをどこから読み込むかを決定する
        let startIndex = (initial == nil) ? 0 : find(_assets, initial!) ?? 0
        // startTimeの設定は初回のみ有効
        var startTime = time

        // リーダーが空の場合、まず先頭のアセットを読み込む
        if _readers.isEmpty && startIndex < _assets.count {
            if let assetreader = AssetReaderFragment(asset:_assets[startIndex],
                rate:_playbackRate, startTime:startTime)
            {
                startTime = kCMTimeZero
                _readers.append(assetreader)
            } else {
                NSLog("Failed to instantiate a AssetReaderFragment.")
            }
        }

        // 読み込みしていないアセットがあれば読み込む
        outer: for (i, asset) in enumerate(_assets[startIndex..<_assets.count]) {

            let actualIndex = i + startIndex
            // 登録済みの最後のアセットを見つけて、それ以降のアセットを
            // 追加対象として読み込む
            if _readers.last?.asset === asset && actualIndex+1 < _assets.count {
                for target_asset in _assets[actualIndex+1..<_assets.count] {

                    // 読み込み済みリーダーの数が上限になれば処理終了
                    if (_readers.count >= kMaximumNumOfReaders) {
                        break outer
                    }

                    if let assetreader = AssetReaderFragment(asset:target_asset,
                        rate:_playbackRate, startTime:startTime)
                    {
                        startTime = kCMTimeZero
                        _readers.append(assetreader)
                    } else {
                        NSLog("Failed to instantiate a AssetReaderFragment.")
                        break outer
                    }
                }
            }
        }
    }
}

/**
*  再生位置を決めるための処理
*/
extension StreamFrameProducer {
    /// 現在のリーダーが指すアセットの位置を返す
    public var _currentAsset: (index: Int, asset: AVAsset)! {
        if let reader = _readers.first {
            if let i = find(self._assets, reader.asset) {
                return (i, reader.asset)
            }
        }
        return nil
    }

    /**
    指定した位置(0.0-1.0)に対するアセットのインデックス番号と、その時刻を計算して返す

    :param: position 一連のムービーにおける位置

    :returns: アセット列におけるインデックスとシーク位置のタプル
    */
    private func _getAssetInfoForPosition(position: Float)
        -> (index:Int, timeStamp:CMTime)?
    {
        let lock = ScopedLock(self)

        if _assets.isEmpty { return nil }
        if _currentAsset == nil { return nil }

        // 0) 指定したポジションを、1.0位置からの時間表現に変換する
        var offset = window * (1.0 - position)

        // 1) 1.0の位置を算出する
        if let one = _getAssetInfoAtOne() {

            // 2) 算出した1.0位置からoffsetTimeを引いた場所を調べて返す
            let targets = reverse(_assets[0 ... one.index])

            if let result = _getIndexAndTime(targets,
                offset: offset + (_assets[one.index].duration - one.time), reverseOrder: true)
            {
                // 算出した値なので、端数が出ないよう1/600スケールに丸めて返す
                let time = CMTimeConvertScale(result.time, 600, .RoundHalfAwayFromZero)
                return (one.index - result.index, time)
            }
        }
        return nil
    }

    /**
    positionが1.0のときのアセットと、その位置(PTS)を返す

    :returns: _assets内の、position=0となるアセットのindexとPresentation Timestamp
    */
    private func _getAssetInfoAtOne() -> (index:Int, time:CMTime)? {
        if let current = _currentAsset {
            // 現在の再生場所を起点にしてposition=1.0地点を探索するが、
            // 先頭のアセットだけを特別視するのを避けて
            // すべてkCMTimeZeroからの位置で計算するため、現在のPTSを
            // 引いた上で1.0となる位置を調べる
            let offset = window * (1.0 - position) + _currentPresentationTimestamp

            let targets = Array(_assets[current.index ..< _assets.count])
            if let resultAtOne = _getIndexAndTime(targets, offset: offset, reverseOrder: false) {
                return (resultAtOne.index + current.index, resultAtOne.time)
            } else {
                // 見つからなかった場合、全アセットの再後端を1.0として扱う
                return (_assets.count-1, _assets.last!.duration)
            }
        }
        return nil
    }

    /**
    アセット列から指定時間ぶんのオフセットがどこにあるかを調べる。該当するアセットが
    無い場合はnilを返す

    :param: targets      探索対象のアセット列
    :param: offset       アセット先頭(reverseOrderがtrueの場合は末尾)からのオフセット
    :param: reverseOrder 逆方向で探索するかどうか。

    :returns: 対象のアセット
    */
    private func _getIndexAndTime(targets:[AVAsset], offset:CMTime, reverseOrder: Bool)
        -> (index: Int, time: CMTime)?
    {
        var offset = offset
        for (i, asset) in enumerate(targets) {

            if offset <= asset.duration {
                let time = reverseOrder ? asset.duration - offset : offset
                return (i, time)
            }
            offset -= asset.duration
        }
        return nil
    }

    /**
    現在の位置を元に、指定したインデックス、プレゼンテーション時間が表すポジションを返す

    :param: index アセットのインデックス。_assets内のインデックス番号のこと。
    :param: time  アセット上の時間

    :returns: 再生位置(0.0-1.0)。値域外の場合はnilを返す
    */
    public func _getPosition(index:Int, time:CMTime) -> Float? {
        let target = (index:index, time:time)

        // 複数アセットを跨いでの差分
        func _calculateDelta(lhs: (index:Int, time:CMTime), rhs: (index:Int, time:CMTime)) -> CMTime {
            var sumTime: CMTime = kCMTimeZero

            // lhsとrhsのどちらが大きい(=1.0に近い)アセットかを調べる
            if lhs.index == rhs.index {
                return lhs.time - rhs.time
            }

            // 中間のアセットのduration合計を求める
            let intermediates = (lhs.index < rhs.index) ?
                _assets[lhs.index+1 ..< rhs.index] : _assets[rhs.index+1 ..< lhs.index]
            sumTime = intermediates.reduce(sumTime) { $0 + $1.duration }

            if lhs.index < rhs.index {
                // (lhsの残り時間 + rhs)の符号反転
                sumTime += (_assets[lhs.index].duration - lhs.time) + rhs.time
                return kCMTimeZero - sumTime
            } else {
                // lhs + rhsの残り時間
                sumTime += lhs.time + (_assets[rhs.index].duration - rhs.time)
                return sumTime
            }
        }

        /*
        「offset = window * position」であることを利用して位置を求める

        offset = window * position
        → position = offset/window
        (※ offset = t(target) - t0 なので)
        → position = (t(target) - t0)/window
        (※ t0 = t1 - window なので)
        → position = (t(target) - t1 + window)/window
        ∴ position = (window + target - t1) / window
        */
        if let t1 = _getAssetInfoAtOne() {
            let numer = window + _calculateDelta(target, t1)
            let position = numer.f / window.f
            return position
        }
        return nil
    }
}