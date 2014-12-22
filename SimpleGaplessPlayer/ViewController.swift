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

/// フレームレート
let kFrameRate: Int = 60

class ViewController: UIViewController {

    @IBOutlet weak var playerView: HKLGLPixelBufferView!
    private var player: HKLAVGaplessPlayer!

    override func viewDidLoad() {
        super.viewDidLoad()

        player.playerView = playerView
        loadVideoAssets()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)

    }

    @IBAction func tapped(sender: AnyObject) {
        player.play()
    }

    /**
    カメラロールから古い順で10個のビデオを取り出し、リーダーをセットアップする
    */
    func loadVideoAssets() {

        let queue = dispatch_queue_create("buildingqueue", DISPATCH_QUEUE_SERIAL)

        let collections = PHAssetCollection.fetchAssetCollectionsWithType(.SmartAlbum, subtype:.SmartAlbumVideos, options: nil)
        collections.enumerateObjectsUsingBlock { [unowned self]  collection, index, stop  in

            // 日付の古い順
            var options = PHFetchOptions()
            options.sortDescriptors = [ NSSortDescriptor(key: "creationDate", ascending: true) ]

            let assets = PHAsset.fetchAssetsInAssetCollection(collection as PHAssetCollection, options: options)
            assets.enumerateObjectsUsingBlock { asset, index, stop in

                // この処理は非同期で行われる
                _ = PHImageManager.defaultManager().requestAVAssetForVideo(asset as PHAsset, options:nil)
                { [unowned self] avasset, audioMix, info in
                    if let avasset = avasset {
                        dispatch_async(queue) {
                            // プロデューサーにアセットを追加
                            self.player.appendAsset(avasset)
                        }
                    }
                }
            }
        }
    }

}
