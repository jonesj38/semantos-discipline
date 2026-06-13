---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/flutter/semantos_demo/macos/Runner/MainFlutterWindow.swift
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.034505+00:00
---

# platforms/flutter/semantos_demo/macos/Runner/MainFlutterWindow.swift

```swift
import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}

```
