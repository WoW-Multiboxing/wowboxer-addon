--[[ WoWBoxer – community links: one table, the same values as the window app and the website's links.json
  (LOG.md [WS-C] "community-links"). Data only; the addon shows them in a copy box (addons cannot open a browser or
  write the clipboard). No GitHub links in the addon UI. ]]
local _, ns = ...
ns.Links = {
  discord = "https://discord.gg/Q5xwbqhKzQ",     -- the WoWBoxer Discord (general)
  discordHelp = "https://discord.gg/3GY3HgF3HC", -- lands in #setup-help
  youtube = "https://www.youtube.com/@WoWBoxerHQ",
  website = "https://wowboxer.com/",
}
--- {key, button label, copy-box title, one line under the title} in the order the UI shows them.
ns.Links.LIST = {
  { "discord", "Discord", "WoWBoxer on Discord", "Chat with other multiboxers, ask questions, share setups." },
  { "youtube", "YouTube", "WoWBoxer on YouTube", "Setup videos and multiboxing guides." },
  { "website", "Website", "wowboxer.com", "Guides, the squad builder and the free window app." },
  { "discordHelp", "Get help", "Help on Discord (#setup-help)", "Ask in #setup-help – paste a problem report there if you made one." },
}
