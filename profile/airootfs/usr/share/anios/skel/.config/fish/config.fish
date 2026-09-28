# AniOS + Immaterial Impulse Fish shell configuration

if status is-interactive
    # Tắt thông báo chào mặc định
    set -g fish_greeting ""

    # Starship prompt nếu có
    if command -v starship >/dev/null 2>&1
        function starship_transient_prompt_func
            starship module character
        end
        if test "dumb" != "linux"
            starship init fish | source
            enable_transience
        end
    end

    # Immaterial Impulse dynamic terminal palette
    set -l imi_seq ~/.local/state/quickshell/user/generated/terminal/sequences.txt
    if set -q TMUX
        set imi_seq ~/.local/state/quickshell/user/generated/terminal/sequences-pane.txt
    end
    if test -f 
        cat 
    end

    # Các alias tiện ích AniOS
    alias ll="ls -lah --color=auto"
    alias la="ls -A --color=auto"
    alias l="ls -CF --color=auto"
    alias fetch="fastfetch"
    alias update="sudo pacman -Syu"
    alias cls="clear"
    alias clear="printf '[2J[3J[1;1H'"

    # Chuyển đổi giao diện desktop
    alias switch-desktop="/usr/local/bin/anios-switch-desktop"

    # Thêm ~/.local/bin vào PATH nếu có
    if test -d "/home/user/.local/bin"
        fish_add_path "/home/user/.local/bin"
    end
end
