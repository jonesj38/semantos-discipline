---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/flutter/semantos_ffi/macos/semantos_ffi.podspec
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.993878+00:00
---

# platforms/flutter/semantos_ffi/macos/semantos_ffi.podspec

```podspec
Pod::Spec.new do |s|
  s.name             = 'semantos_ffi'
  s.version          = '1.0.0'
  s.summary          = 'Semantos FFI bindings for Flutter (macOS)'
  s.homepage         = 'https://semantos.io'
  s.license          = { :type => 'Proprietary' }
  s.author           = { 'Semantos' => 'hello@semantos.io' }
  s.source           = { :path => '.' }
  s.platform         = :osx, '10.15'

  # For macOS dev: link libsemantos.dylib built by zig
  s.vendored_libraries = 'lib/libsemantos.dylib'
end

```
