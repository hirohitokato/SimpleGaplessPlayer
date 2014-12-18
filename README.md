# SimpleGaplessPlayer

A simple player sample that can play multiple assets without gap.

## What is this?

AVQueuePlayer is used to play a number of items in sequence. But the short gap that we can easily notice them is laid between movies. This project shows how to play multiple assets without gap between assets.

The app loads 10 video assets from camera-roll via Phots.framework when it is launched. Double tap the screen, it plays them with no gap.

## How to remove gaps?

See ViewController.swift. It creates AVAssetReaderVideoCompositionOutput, which is a subclass of AVAssetReader,  enables you to read each frames based on the video composition settings.

## License
New BSD License.
