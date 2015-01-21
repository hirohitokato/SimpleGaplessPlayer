//
//  ViewController.swift
//  LearningVideoComposition
//
//  Created by Hirohito Kato on 2014/12/17.
//  Copyright (c) 2014年 Hirohito Kato. All rights reserved.
//

import UIKit
import Photos
import AVFoundation
import HKLAVGaplessPlayer

class ViewController: UIViewController {

    @IBOutlet weak var playerView: HKLGLPixelBufferView!
    @IBOutlet weak var msgLabel: UILabel!
    @IBOutlet weak var rateLabel: UILabel!
    @IBOutlet weak var positionSlider: UISlider!
    @IBOutlet weak var modeControl: UISegmentedControl!

    enum PlayerMode: Int {
        case Playback  = 0
        case Streaming = 1
    }

    private let _player = HKLAVGaplessPlayer()
    private var _timer: NSTimer!

    override func viewDidLoad() {
        super.viewDidLoad()

        _player.delegate = playerView as? HKLAVGaplessPlayerDelegate
        loadVideoAssets()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)

        _timer = NSTimer.scheduledTimerWithTimeInterval(
            0.2, target: self, selector: "updateUI:",
            userInfo: nil, repeats: true)
    }

    override func viewWillDisappear(animated: Bool) {
        super.viewWillDisappear(animated)

        _timer.invalidate()
    }

    @IBAction func tapped(sender: AnyObject) {
        if _player.isPlaying {
            _player.pause()
        } else {
            _player.play()
        }
    }

    @IBAction func swipedToLeft(sender: AnyObject) {
        _player.advanceToNextAsset()
    }

    @IBAction func sliderUpdated(sender: UISlider) {
        _player.play(_player.rate, position: sender.value)
    }

    @IBAction func rateChanged(sender: UISlider) {
        rateLabel.text = "rate: \(sender.value)"
        // rate==0.0のときはAsIsモードで再生
        let newRate = sender.value>0.0 ? sender.value : HKLAVGaplessPlayerPlayRateAsIs
        _player.play(newRate)
    }

    @IBAction func modeChanged(sender: UISegmentedControl) {
        switch sender.selectedSegmentIndex {
        case PlayerMode.Playback.rawValue:
            _player.playbackMode = .Playback
        case PlayerMode.Streaming.rawValue:
            _player.playbackMode = .Streaming
        default:
            println("do nothing for mode:\(sender.selectedSegmentIndex)")
        }
    }

    @objc func updateUI(timer: NSTimer) {
        msgLabel.text = "cpu: \(cpu_usage_in_percent())% pos:\(_player.position)"
        positionSlider.value = _player.position
    }

    /**
    カメラロールから古い順で10個のビデオを取り出し、リーダーをセットアップする
    */
    private func loadVideoAssets() {

        let queue = dispatch_queue_create("buildingqueue", DISPATCH_QUEUE_SERIAL)

        // 収集したアセットをいったん格納する（最終的にindex順でソートして格納）
        var avassets = [(Int, AVAsset)]()

        // 「ビデオ」のスマートアルバムから収集
        let collections = PHAssetCollection.fetchAssetCollectionsWithType(.SmartAlbum, subtype:.SmartAlbumVideos, options: nil)
        collections.enumerateObjectsUsingBlock {
            [unowned self]  collection, index, stop  in
            let collection = collection as PHAssetCollection

            // 日付の古い順に取得
            var options = PHFetchOptions()
            options.sortDescriptors = [ NSSortDescriptor(key: "creationDate", ascending: true) ]

            var failed: Int = 0

            let assets = PHAsset.fetchAssetsInAssetCollection(collection, options: options)
            assets.enumerateObjectsUsingBlock {
                phAsset, index, stop in
                let phAsset = phAsset as PHAsset

                // オリジナルのアセットを取得するよう指定
                let options = PHVideoRequestOptions()
                options.version = .Original

                // この処理は非同期で行われるので注意
                _ = PHImageManager.defaultManager().requestAVAssetForVideo(phAsset, options:options) {
                    avasset, audioMix, info in

                    // プレイヤーに日付順で追加できるよう試みる
                    if let avasset = avasset {
                        dispatch_async(queue) { // シリアライズ(配列操作を排他)
                            avassets.append((index,avasset))
                            if avassets.count + failed == assets.count {
                                println("Finished gathering video assets. (\(failed) failed)")
                                // プロデューサーにアセットを追加
                                sort(&avassets) { $0.0 < $1.0 }
                                for (_, a) in avassets {
                                    self._player.appendAsset(a)
                                }
                            }
                        }
                    } else {
                        println("request asset failed:\(avasset)")
                        dispatch_async(queue) { let dummy = ++failed }
                    }
                }
            }
        }
    }
}
