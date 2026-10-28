# Template for the cask in Osmait/homebrew-tap. The release workflow fills in
# the version and checksum and pushes it to the tap.
cask "agentch" do
  version "{{VERSION}}"
  sha256 "{{SHA256}}"

  url "https://github.com/Osmait/agentch/releases/download/v#{version}/Agentch-#{version}.dmg"
  name "Agentch"
  desc "Shows your AI coding subscription limits in the notch"
  homepage "https://github.com/Osmait/agentch"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :sonoma"

  app "Agentch.app"

  uninstall quit: "com.saulburgos.agentch"

  zap trash: "~/Library/Preferences/com.saulburgos.agentch.plist"
end
