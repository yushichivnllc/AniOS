# AniOS Fish shell configuration

if status is-interactive
    # Tắt thông báo chào mặc định
    set -g fish_greeting ""

    # Các alias tiện ích
    alias ll="ls -lah --color=auto"
    alias la="ls -A --color=auto"
    alias l="ls -CF --color=auto"
    alias fetch="fastfetch"
    alias update="sudo pacman -Syu"
    alias cls="clear"

    # Thêm ~/.local/bin vào PATH nếu có
    if test -d "$HOME/.local/bin"
        fish_add_path "$HOME/.local/bin"
    end
end
