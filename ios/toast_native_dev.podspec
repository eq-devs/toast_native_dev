Pod::Spec.new do |s|
  s.name             = 'toast_native_dev'
  s.version          = '0.0.1'
  s.summary          = 'Native toast notifications above Flutter widgets and WebViews.'
  s.description      = 'Shows toast notifications using UIWindow overlays, appearing above Hybrid Composition WebViews.'
  s.homepage         = 'https://github.com/eq-devs/toast_native_dev'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'eq-devs' => 'estaykargabay1206@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '13.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version    = '5.0'
end
