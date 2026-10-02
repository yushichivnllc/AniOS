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

    # Màu cú pháp Gura Blue cho chính fish (starship chỉ vẽ dấu nhắc).
    # Ở chế độ imi, dãy escape của Matugen nạp phía trên sẽ ưu tiên hơn.
    set -g fish_color_normal eaf4fd
    set -g fish_color_command 2f6be8
    set -g fish_color_keyword 7e9bf0
    set -g fish_color_quote 3ec3d8
    set -g fish_color_redirection 4ea6ea
    set -g fish_color_end 7e9bf0
    set -g fish_color_error d8404f
    set -g fish_color_param f2f8fe
    set -g fish_color_comment 55708f
    set -g fish_color_match 4ea6ea
    set -g fish_color_search_match --background=1e4266
    set -g fish_color_selection --background=1e4266
    set -g fish_color_operator 4ea6ea
    set -g fish_color_escape 7e9bf0
    set -g fish_color_autosuggestion 55708f
    set -g fish_color_cwd 2f6be8
    set -g fish_color_user 3ec3d8
    set -g fish_color_host 4ea6ea
    set -g fish_color_status d8404f
    set -g fish_pager_color_prefix 4ea6ea
    set -g fish_pager_color_completion eaf4fd
    set -g fish_pager_color_description 55708f
    set -g fish_pager_color_progress 55708f
    set -g fish_pager_color_selected_background --background=1e4266

    # Các alias tiện ích AniOS
    alias ll="ls -lah --color=auto"
    alias la="ls -A --color=auto"
    alias l="ls -CF --color=auto"
    alias fetch="fastfetch"
    alias update="/usr/local/bin/anios-update"
    # yay (trợ lý AUR) đã cài sẵn trong ảnh
    alias update-aur="/usr/local/bin/anios-update --aur"
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
