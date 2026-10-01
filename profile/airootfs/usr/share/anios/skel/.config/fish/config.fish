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
    if test -f $imi_seq
        cat $imi_seq
    end

    # Màu cú pháp Tokyo Night cho chính fish (starship chỉ vẽ dấu nhắc).
    # Ở chế độ imi, dãy escape của Matugen nạp phía trên sẽ ưu tiên hơn.
    set -g fish_color_normal c0caf5
    set -g fish_color_command 7aa2f7
    set -g fish_color_keyword bb9af7
    set -g fish_color_quote 9ece6a
    set -g fish_color_redirection 7dcfff
    set -g fish_color_end bb9af7
    set -g fish_color_error f7768e
    set -g fish_color_param d9deea
    set -g fish_color_comment 565f89
    set -g fish_color_match 7dcfff
    set -g fish_color_search_match --background=2d3446
    set -g fish_color_selection --background=2d3446
    set -g fish_color_operator 7dcfff
    set -g fish_color_escape bb9af7
    set -g fish_color_autosuggestion 565f89
    set -g fish_color_cwd 7aa2f7
    set -g fish_color_user 9ece6a
    set -g fish_color_host 7dcfff
    set -g fish_color_status f7768e
    set -g fish_pager_color_prefix 7dcfff
    set -g fish_pager_color_completion c0caf5
    set -g fish_pager_color_description 565f89
    set -g fish_pager_color_progress 565f89
    set -g fish_pager_color_selected_background --background=2d3446

    # Các alias tiện ích AniOS
    alias ll="ls -lah --color=auto"
    alias la="ls -A --color=auto"
    alias l="ls -CF --color=auto"
    alias fetch="fastfetch"
    alias update="sudo pacman -Syu"
    # yay (trợ lý AUR) đã cài sẵn trong ảnh
    alias update-aur="yay -Syu"
    alias aur-search="yay -Ss"
    alias cls="clear"
    alias clear="printf '[2J[3J[1;1H'"

    # Chuyển đổi giao diện desktop
    alias switch-desktop="/usr/local/bin/anios-switch-desktop"

    # Thêm ~/.local/bin vào PATH nếu có
    if test -d "$HOME/.local/bin"
        fish_add_path "$HOME/.local/bin"
    end
end
