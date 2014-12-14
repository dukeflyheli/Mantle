Pod::Spec.new do |s|
  s.name     = 'Mantle'
  s.version  = '1.5.1'
  s.license  = 'MIT'
  s.summary  = 'Expressive, flexible, and powerful stylesheets for UIView and friends.'
  s.homepage = 'https://github.com/Mantle/Mantle'
  s.author   = { 'Jonas Budelmann' => 'jonas.budelmann@gmail.com' }
  s.social_media_url = "http://twitter.com/cloudkite"

  s.source   = { :git => 'https://github.com/github/Mantle.git', :tag => '1.5.1' }

  s.description = %{
    Not CSS. Instead of trying to force UIKit to fit CSS syntax, properties, conventions and constructs.
    Classy is a stylesheet system built from the ground up to work in harmony with UIKit.
    It borrows the best ideas from CSS and introduces new syntax, conventions and constructs where appropriate.
  }

  s.source_files = 'Mantle'
  s.subspec 'extobjc' do |ss|
    ss.source_files = 'Mantle/extobjc'
  end
  
  s.ios.frameworks = 'Foundation'

  s.ios.deployment_target = '6.0'
  s.requires_arc = true
end