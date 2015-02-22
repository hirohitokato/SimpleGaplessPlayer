//
//  AssetReaderFragment.swift
//  SimpleGaplessPlayer
//
//  Created by Hirohito Kato on 2014/12/22.
//  Copyright (c) 2014年 Hirohito Kato. All rights reserved.
//

import Foundation
import AVFoundation

struct FrameData : Printable, DebugPrintable {
    let sampleBuffer: CMSampleBuffer
    let duration: CMTime

    var description: String {
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        return "sbuf:{\(pts.value)/\(pts.timescale)} {duration:\(duration.value)/\(duration.timescale)}"
    }
    var debugDescription: String {
        return "\(sampleBuffer)\nduration:{\(duration.value)/\(duration.timescale)}"
    }
}

/**
アセットリーダーと元アセットとを管理する型。時間も管理することで、60fps以下の
ムービーでも滞りなく再生できるようにする
*/
internal class AssetReaderFragment: NSObject {
    let asset: AVAsset
    let URL: NSURL!
    let rate: Float
    let startTime: CMTime
    let endTime: CMTime
    let preferredTransform: CGAffineTransform

    init!(asset:AVAsset, rate:Float=1.0, startTime:CMTime=kCMTimeZero, var endTime:CMTime=kCMTimePositiveInfinity) {
        self.asset = asset
        self.rate = rate
        self.startTime = startTime
        self.endTime = endTime
        self.preferredTransform = asset.preferredTransform
        self.URL = (asset as? AVURLAsset)?.URL

        super.init()

        // リーダーとなるコンポジションを作成する
        if rate == HKLAVGaplessPlayerPlayRateAsIs {
            if let result = _buildAsIsComposition(asset, startTime:startTime, endTime:endTime, rate:rate) {
                _reader = result.reader
                _fragmentDuration = result.duration
                _frameInterval = result.frameInterval
            }
        } else {
            if let result = _buildComposition(asset, startTime:startTime, endTime:endTime, rate:rate) {
                _reader = result.reader
                _fragmentDuration = result.duration
                _frameInterval = result.frameInterval
            }
        }
        if _reader == nil {
            // 作成失敗
            NSLog("Failed to build a composition for asset.")
            return nil
        }
        _output = _reader.outputs.first as! AVAssetReaderOutput

        // 読み込み開始
        if self._reader.startReading() == false {
            NSLog("Failed to start a reader:\(self._reader)\n error:\(self._reader.error)")
            return nil
        }
    }

    deinit {
        _reader?.cancelReading()
        asset.cancelLoading()
    }

    /**
    内包しているAVAssetReaderのstatusプロパティの値(AVAssetReaderStatus)を返す。
    */
    var status: AVAssetReaderStatus { return _reader.status }

    /**
    アセットの再生時間を返す
    */
    var duration: CMTime { return _fragmentDuration }

    /**
    再生開始位置を加味した、現在のPTSを返す
    */
    var currentPresentationTimestamp: CMTime { return startTime + _lastPresentationTimestamp }

    /**
    作成したリーダーから次のフレームを同期取得して、再生時間と共に返す

    :returns: A FrameData struct referencing the output sample buffer.
    */
    func copyNextFrame() -> FrameData! {
        if let sbuf = _output.copyNextSampleBuffer() {
            _lastPresentationTimestamp = CMSampleBufferGetPresentationTimeStamp(sbuf)
            return FrameData(sampleBuffer: sbuf, duration: _frameInterval)
        }
        return nil
    }

    // MARK: Private variables & methods

    private var _reader: AVAssetReader!
    private var _output: AVAssetReaderOutput!
    private var _fragmentDuration: CMTime!
    private var _frameInterval: CMTime = kCMTimeIndefinite
    private var _lastPresentationTimestamp: CMTime = kCMTimeZero

    /**
    アセットの指定範囲をフレーム単位で取り出すためのリーダーを作成する。
    具体的には再生時間帯を限定したコンポジションを作成し、そのフレームを取り出すための
    アウトプットを作成している

    :param: asset     読み出し元となるアセット
    :param: startTime アセットの読み出し開始位置（デフォルト：先頭）
    :param: endTime   アセットの読み出し終了位置（デフォルト：末尾）
    :param: rate      再生速度。1.0が等速再生、2.0が２倍速再生となる

    :returns: アセットリーダー
    */
    private func _buildComposition(asset:AVAsset,
        startTime:CMTime=kCMTimeZero, var endTime:CMTime=kCMTimePositiveInfinity,
        rate:Float=1.0)
        -> (reader:AVAssetReader, duration:CMTime, frameInterval:CMTime)!
    {
        var error: NSError? = nil

        assert(rate>0.0, "Unable to set rate less than or equal to 0.0!!")

        // ビデオトラックを抽出
        /* durationを調べるためだけに使う */
        if asset.tracksWithMediaType(AVMediaTypeVideo).count == 0 {
            NSLog("Video track is empty. the asset:\((asset as? AVURLAsset)?.URL.lastPathComponent!) contains \(asset.tracks)")
            return nil
        }
        let videoTrack = asset.tracksWithMediaType(AVMediaTypeVideo)[0] as! AVAssetTrack

        // 引数で指定した再生範囲を「いつから何秒間」の形式に変換
        if endTime > videoTrack.timeRange.duration {
            endTime = videoTrack.timeRange.duration
        }
        let duration = endTime - startTime
        let timeRange = CMTimeRangeMake(startTime, duration)

        // durationがほぼゼロの場合はコンポジションを作成できないのでnilを返す
        if duration < kCMTimeZero || duration.isNearlyEqualTo(kCMTimeZero, 1.0/60.0) {
            NSLog("duration(\(duration)) is less than or equal to 0")
            return nil
        }

        /* 作成するコンポジションとリーダーの構造
        *
        * [AVAssetReaderVideoCompositionOutput]: ビデオフレーム取り出し口
        * │└ [AVAssetReader] ↑[videoTracks] : コンポジション上のvideoTrackを読み出し元に指定
        * │    └ [AVMutableComposition]      : 再生時間帯の指定
        * │        └ [videoTrack in AVAsset] : ソースに使うビデオトラック
        * └ [AVVideoComposition]              : フレームレート指定
        */

        // アセットのビデオトラックを配置するためのコンポジションを作成、配置
        /* 2015/01/05 memo:
        下のコードのようにAVMutableCompositionTrackを作ってトラックを挿入する方法だと
        一部のアセットで再生できない問題が発生してしまった。

        let compoVideoTrack = composition.addMutableTrackWithMediaType(AVMediaTypeVideo,
          preferredTrackID: Int32(kCMPersistentTrackID_Invalid))
        if !compoVideoTrack.insertTimeRange(timeRange, ofTrack: videoTrack, atTime: kCMTimeZero, error: &error) {…
        
        何か理由があるのだろうが、現状では解決できなかったため、norio_nomura氏による
        下記コード（AVMutableCompositionにアセットをそのまま入れる）を使用する。
        */
        let composition = AVMutableComposition()
        if !composition.insertTimeRange(timeRange, ofAsset: asset, atTime: kCMTimeZero, error: &error) {
            NSLog("Failed to insert a video track(from:\(startTime) to:\(endTime)) to composition:\(error)")
            return nil
        }

        // 60fps以下の場合、60fpsで出力出来るようスケールしたいが、scaleTimeRange()は
        // frameDuration以下のfpsのときには、読み出そうとしてもエラーになってしまう模様。
        // → DisplayLinkの複数回の呼び出しで同じ画像を返せるよう、ロジックを変更する
        //        let stretchRate = max(videoTrack.minFrameDuration.f, (1.0/60)) * 60.0
        //        println("stretchRate:\(timeRange) (\(timeRange.duration)-> \(timeRange.duration*stretchRate))")
        //        composition.scaleTimeRange(timeRange, toDuration:timeRange.duration*0.5)

        var displayDuration: CMTime = kCMTimeInvalid

        // フレームレート指定のためにビデオコンポジションを作成
        let videoComposition = AVMutableVideoComposition(propertiesOfAsset: asset)
        if rate == HKLAVGaplessPlayerPlayRateAsIs {
            // As Isで表示する場合、アセットのフレームをそのまま取り出せるよう
            // videoTrackのminFrameDurationをそのまま利用する
            videoComposition.frameDuration = videoTrack.minFrameDuration

            // フレームの時間を1回/VSYNCにする
            displayDuration = FrameDurationIsAsIs
        } else {
            // As Isではない場合、アセットのfpsによらずrateの再生速度となるよう
            // 計算した値を利用する
            let referenceRate = Float(playbackFrameRate) / rate
            videoComposition.frameDuration =
                CMTime(value: 1, Int(min(referenceRate, videoTrack.nominalFrameRate)))

            // 再生時間とフレーム数から、正確なフレーム時間を計算する
            displayDuration = CMTime(seconds: duration.f / ceil(duration.f / videoComposition.frameDuration.f) / rate )
        }

        // アセットリーダーに接続するアウトプット(出力口)として、
        // ビデオコンポジションを指定できるAVAssetReaderVideoCompositionOutputを作成
        // 注意点：
        // - このビデオトラックにはコンポジション上のビデオトラックを指定すること
        // - IOSurfaceで作成しなくても再生できるが、念のため付けておく
        let compoVideoTracks = composition.tracksWithMediaType(AVMediaTypeVideo)
        var output = AVAssetReaderVideoCompositionOutput(videoTracks: compoVideoTracks,
            videoSettings: [kCVPixelBufferPixelFormatTypeKey : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                kCVPixelBufferIOSurfacePropertiesKey : [:]])
        output.videoComposition = videoComposition

        // サンプルバッファを取り出すときにデータをコピーしない（負荷軽減）
        output.alwaysCopiesSampleData = false

        // コンポジションからアセットリーダーを作成し、アウトプットを接続
        if let reader = AVAssetReader(asset: composition, error: &error) {
            if reader.canAddOutput(output) {
                reader.addOutput(output)
            }
            return (reader, duration, displayDuration)
        } else {
            NSLog("Failed to instantiate a reader for a composition:\(error)")
        }
        
        return nil
    }

    private func _buildAsIsComposition(asset:AVAsset,
        startTime:CMTime=kCMTimeZero, var endTime:CMTime=kCMTimePositiveInfinity,
        rate:Float=HKLAVGaplessPlayerPlayRateAsIs)
        -> (reader:AVAssetReader, duration:CMTime, frameInterval:CMTime)!
    {
        var error: NSError? = nil

        // ビデオトラックを抽出
        /* durationを調べるためだけに使う */
        if asset.tracksWithMediaType(AVMediaTypeVideo).count == 0 {
            NSLog("Video track is empty. the asset:\((asset as? AVURLAsset)?.URL.lastPathComponent!) contains \(asset.tracks)")
            return nil
        }
        let videoTrack = asset.tracksWithMediaType(AVMediaTypeVideo)[0] as! AVAssetTrack

        // 引数で指定した再生範囲を「いつから何秒間」の形式に変換
        if endTime > videoTrack.timeRange.duration {
            endTime = videoTrack.timeRange.duration
        }
        let duration = endTime - startTime
        let timeRange = CMTimeRangeMake(startTime, duration)

        // durationがほぼゼロの場合はコンポジションを作成できないのでnilを返す
        if duration < kCMTimeZero || duration.isNearlyEqualTo(kCMTimeZero, 1.0/60.0) {
            NSLog("duration(\(duration)) is less than or equal to 0")
            return nil
        }

        /* 作成するコンポジションとリーダーの構造
        *
        * [AVAssetReaderTrackOutput]         : ビデオフレーム取り出し口
        * └ [AVAssetReader]                 : コンポジション上のvideoTrackを読み出し元に指定
        *     └ [AVMutableComposition]      : 再生時間帯の指定
        *         └ [videoTrack in AVAsset] : ソースに使うビデオトラック
        */
        let composition = AVMutableComposition()
        if !composition.insertTimeRange(timeRange, ofAsset: asset, atTime: kCMTimeZero, error: &error) {
            NSLog("Failed to insert a video track(from:\(startTime) to:\(endTime)) to composition:\(error)")
            return nil
        }

        // フレームの時間を1回/VSYNCにする
        var displayDuration = FrameDurationIsAsIs

        // アセットリーダーに接続するアウトプット(出力口)として、
        // copyNextSampleBuffer()でハングする可能性の低いAVAssetReaderTrackOutputを使う
        let compoVideoTrack = composition.tracksWithMediaType(AVMediaTypeVideo).first as! AVAssetTrack
        var output = AVAssetReaderTrackOutput(track: compoVideoTrack,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                kCVPixelBufferIOSurfacePropertiesKey : [:]])

        // サンプルバッファを取り出すときにデータをコピーしない（負荷軽減）
        output.alwaysCopiesSampleData = false

        // コンポジションからアセットリーダーを作成し、アウトプットを接続
        if let reader = AVAssetReader(asset: composition, error: &error) {
            if reader.canAddOutput(output) {
                reader.addOutput(output)
                return (reader, duration, displayDuration)
            }
        } else {
            NSLog("Failed to instantiate a reader for a composition:\(error)")
        }
        
        return nil
    }
}
