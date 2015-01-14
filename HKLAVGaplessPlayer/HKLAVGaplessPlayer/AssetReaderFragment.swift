//
//  AssetReaderFragment.swift
//  SimpleGaplessPlayer
//
//  Created by Hirohito Kato on 2014/12/22.
//  Copyright (c) 2014年 Hirohito Kato. All rights reserved.
//

import Foundation
import AVFoundation

/**
アセットリーダーと元アセットとを管理する型。時間も管理することで、60fps以下の
ムービーでも滞りなく再生できるようにする
*/
internal class AssetReaderFragment: NSObject {
    let asset: AVAsset
    let rate: Float
    let startTime: CMTime
    let endTime: CMTime

    private(set) var frameInterval: CMTime = kCMTimeIndefinite
    let preferredTransform: CGAffineTransform

    init!(asset:AVAsset, rate:Float=1.0, startTime:CMTime=kCMTimeZero, var endTime:CMTime=kCMTimePositiveInfinity) {
        self.asset = asset
        self.rate = rate
        self.startTime = startTime
        self.endTime = endTime
        self.preferredTransform = asset.preferredTransform
        
        super.init()

        // リーダーとなるコンポジションを作成する
        if let result = _buildComposition(asset, startTime:startTime, endTime:endTime, rate:rate) {
            /*
            (reader, frameInterval) = result で記述すると、以下のコンパイルエラー：
            "Cannot express tuple conversion '(AVAssetReader, CMTime)' to '(AVAssetReader!, CMTime)'"
            が出てしまうため、分解して代入するようにした
            */
            (_reader, frameInterval) = (result.0, result.1)
            _output = _reader.outputs.first as? AVAssetReaderOutput
        } else {
            // 作成失敗
            NSLog("Failed to build a composition for asset.")
            return nil
        }

        // 読み込み開始
        if self._reader.startReading() == false {
            NSLog("Failed to start a reader:\(self._reader)\n error:\(self._reader.error)")
            return nil
        }
    }

    /**
    内包しているAVAssetReaderのstatusプロパティの値(AVAssetReaderStatus)を返す。
    */
    var status: AVAssetReaderStatus {
        return _reader.status
    }

    /**
    作成したリーダーから次のサンプルバッファ(コピー)を同期取得して返す

    :returns: A CMSampleBuffer object referencing the output sample buffer.
    */
    func copyNextSampleBuffer() -> CMSampleBuffer! {
        return _output.copyNextSampleBuffer()
    }

    // MARK: Private variables & methods

    private let _reader: AVAssetReader!
    private let _output: AVAssetReaderOutput!

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
        -> (AVAssetReader, CMTime)!
    {
        var error: NSError? = nil

        assert(rate>0.0, "Unable to set rate to 0.0!!")
        // ビデオトラックを抽出
        /* durationを調べるためだけに使う */
        if asset.tracksWithMediaType(AVMediaTypeVideo).count == 0 {
            NSLog("Somehow the number of video track is zero. the asset:\((asset as AVURLAsset).URL.lastPathComponent) contains \(asset.tracks)")
            return nil
        }
        let videoTrack = asset.tracksWithMediaType(AVMediaTypeVideo)[0] as AVAssetTrack

        // 引数で指定した再生範囲を「いつから何秒間」の形式に変換
        if endTime > videoTrack.timeRange.duration {
            endTime = videoTrack.timeRange.duration
        }
        let duration = endTime - startTime
        let timeRange = CMTimeRangeMake(startTime, duration)

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

        // アセットリーダーに接続するアウトプット(出力口)として、
        // ビデオコンポジションを指定できるAVAssetReaderVideoCompositionOutputを作成
        // 注意点：
        // - このビデオトラックにはコンポジション上のビデオトラックを指定すること
        // - IOSurfaceで作成しなくても再生できるが、念のため付けておく
        let compoVideoTracks = composition.tracksWithMediaType(AVMediaTypeVideo)
        var output = AVAssetReaderVideoCompositionOutput(videoTracks: compoVideoTracks,
            videoSettings: [kCVPixelBufferPixelFormatTypeKey : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                kCVPixelBufferIOSurfacePropertiesKey : [:]])

        var displayDuration: CMTime = kCMTimeInvalid

        if rate == HKLAVGaplessPlayerPlayRateAsIs {
            displayDuration = kCMTimeNegativeInfinity
        } else {
            // フレームレート指定のためにビデオコンポジションを作成・利用(Max.60fps)
            let videoComposition = AVMutableVideoComposition(propertiesOfAsset: asset)
            let referenceRate = Float(kPlaybackFrameRate) / rate
            videoComposition.frameDuration =
                CMTime(value: 1, Int(min(referenceRate, videoTrack.nominalFrameRate)))
            output.videoComposition = videoComposition

            // 再生時間とフレーム数から、正確なフレーム時間を計算する
            displayDuration = CMTime(seconds: duration.f / ceil(duration.f / output.videoComposition.frameDuration.f) / rate )
        }

        // サンプルバッファを取り出すときにデータをコピーしない（負荷軽減）
        output.alwaysCopiesSampleData = false

        // コンポジションからアセットリーダーを作成し、アウトプットを接続
        if let reader = AVAssetReader(asset: composition, error: &error) {
            if reader.canAddOutput(output) {
                reader.addOutput(output)
            }
            return (reader, displayDuration)
        } else {
            NSLog("Failed to instantiate a reader for a composition:\(error)")
        }
        
        return nil
    }
}
