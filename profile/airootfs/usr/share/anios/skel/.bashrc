# ~/.bashrc - Cấu hình shell Bash cho AniOS
#
# Không thực thi nếu không phải phiên tương tác
[[ $- != *i* ]] && return

# Lịch sử dòng lệnh (Command history)
HISTCONTROL=ignoreboth:erasedups
HISTSIZE=10000
HISTFILESIZE=20000
shopt -s histappend
shopt -s checkwinsize

# Tự động sửa lỗi gõ nhỏ khi cd
shopt -s cdspell 2>/dev/null || true

# Trình soạn thảo mặc định
export EDITOR=nano
export VISUAL=nano
export PAGER=less

# Thêm đường dẫn người dùng vào PATH
if [[ -d "$HOME/.local/bin" && ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    PATH="$HOME/.local/bin:$PATH"
fi

# Màu sắc cho lệnh ls và grep
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    alias dir='dir --color=auto'
    alias vdir='vdir --color=auto'
    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi

# Các alias tiện ích thông dụng
alias ll='ls -lah --color=auto'
alias la='ls -A --color=auto'
alias l='ls -CF --color=auto'
alias fetch='fastfetch'
alias update='sudo pacman -Syu'
# yay (trợ lý AUR) đã cài sẵn trong ảnh: cập nhật và cài thêm gói ngoài kho chính thức
alias update-aur='yay -Syu'
alias aur-search='yay -Ss'
alias cls='clear'

# Dấu nhắc lệnh (Prompt) mang màu sắc AniOS
if [ "$USER" = "root" ]; then
    PS1='\[\033[01;31m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]# '
else
    PS1='\[\033[01;34m\]anios\[\033[00m\]@\[\033[01;36m\]live\[\033[00m\]:\[\033[01;32m\]\w\[\033[00m\]\$ '
fi
