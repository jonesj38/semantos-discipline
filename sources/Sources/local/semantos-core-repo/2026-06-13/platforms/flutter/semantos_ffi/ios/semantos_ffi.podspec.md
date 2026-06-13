---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/flutter/semantos_ffi/ios/semantos_ffi.podspec
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.992574+00:00
---

# platforms/flutter/semantos_ffi/ios/semantos_ffi.podspec

```podspec
Pod::Spec.new do |s|
  s.name             = 'semantos_ffi'
  s.version          = '1.0.0'
  s.summary          = 'Semantos FFI bindings for Flutter (iOS)'
  s.description      = <<-DESC
    Native Semantos kernel linked as an XCFramework.
    Provides cell read/write, capability verification, and
    adapter callback registration via a C ABI boundary.
  DESC
  s.homepage         = 'https://semantos.io'
  s.license          = { :type => 'Proprietary' }
  s.author           = { 'Semantos' => 'hello@semantos.io' }
  s.source           = { :path => '.' }
  s.platform         = :ios, '13.0'
  s.swift_version    = '5.0'

  # Phase 30F delivers Semantos.xcframework here
  s.vendored_frameworks = 'Frameworks/Semantos.xcframework'

  # Fallback: if no xcframework yet, link the static lib directly
  # s.vendored_libraries = 'lib/libsemantos.a'
  # s.pod_target_xcconfig = { 'OTHER_LDFLAGS' => '-lsemantos' }
end

```
