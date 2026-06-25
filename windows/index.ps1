Install-Archive `
    -Id "wezterm" `
    -Url "https://github.com/wezterm/wezterm/releases/download/nightly/WezTerm-windows-nightly.zip" `
    -Sha256Url "https://github.com/wezterm/wezterm/releases/download/nightly/WezTerm-windows-nightly.zip.sha256" `
    -To "apps:WezTerm" `
    -StripComponents 1

Install-Archive `
    -Id "termscp" `
    -Url "https://github.com/veeso/termscp/releases/download/v1.1.1/termscp-v1.1.1-x86_64-pc-windows-msvc.zip" `
    -To "apps:TermSCP" `
    -Cache ImmutableUrl

Install-Archive `
    -Id "cascadia-next-nerd-font" `
    -Url "https://github.com/LiLittleCat/Cascadia-Next-Nerd-Font/releases/download/v1.0.1/CascadiaNextSCNF-ttc.tar.gz" `
    -To "fonts:CascadiaNext" `
    -Cache ImmutableUrl `
    -InstallFont

Copy-Config `
    -From "./user/.wezterm.lua" `
    -To "user:.wezterm.lua"

Link-File `
    -From "apps:TermSCP/termscp.exe" `
    -To "bin:termscp.exe"
