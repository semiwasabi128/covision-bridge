Pod::Spec.new do |s|
  s.name           = 'BridgeMobile'
  s.version        = '1.0.0'
  s.summary        = 'Native iOS SDK for Bridge App (mobile_bridge_client bridge)'
  s.description    = <<-DESC
    Connect to Bridge Desktop Gateway via WebSocket.
    Includes 85 BridgeDS design tokens via UIColor.bridge() extension.
    Generated from Flutter lib/services/mobile_bridge_client.dart
  DESC
  s.homepage       = 'https://github.com/bridge-app/bridge-mobile'
  s.license        = { :type => 'MIT', :file => '../LICENSE.md' }
  s.author         = { 'Bridge Team' => 'team@bridge.app' }
  s.source         = { :git => 'https://github.com/bridge-app/bridge-mobile.git', :tag => "v#{s.version}" }

  s.ios.deployment_target = '13.0'
  s.swift_version = '5.0'

  s.source_files = '*.{swift,h,m}'
end
