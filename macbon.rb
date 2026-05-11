cask "macbon" do
  version "1.1.0"
  sha256 "b732d21bfe0790fcc30716b466da36a75e3fed5939b3e47c50b2276df59dd1d9"

  url "https://github.com/howardfung7-prog/macbon/releases/download/v#{version}/MacBon.dmg"
  name "MacBon"
  desc "Tap your MacBook chassis to trigger actions using the built-in accelerometer"
  homepage "https://macbon.tech"

  depends_on macos: ">= :ventura"
  depends_on arch: :arm64

  app "MacBon.app"

  zap trash: [
    "~/Library/Preferences/com.macbon.MacBon.plist",
    "~/MacBon",
  ]
end
