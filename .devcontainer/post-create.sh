#!/usr/bin/env bash

if [ -f package.json ]; then
  bash -i -c "nvm install --lts && nvm install-latest-npm"
  npm i
  npm run build
fi

# Install Python + pip deps (if this repo uses them)
if [ -f requirements.txt ]; then
  if ! command -v python3 >/dev/null 2>&1; then
    sudo apt-get update
    sudo apt-get install -y python3
  fi

  if ! python3 -m pip --version >/dev/null 2>&1; then
    sudo apt-get update
    sudo apt-get install -y python3-pip
  fi

  # Ensure user-level pip bins (e.g. `jupyter`) are on PATH for zsh sessions
  if ! grep -q 'HOME/.local/bin' ~/.zshrc 2>/dev/null; then
    echo -e '\nexport PATH="$HOME/.local/bin:$PATH"' >>~/.zshrc
  fi

  # Some images only provide `pip3`; add a `pip` shim for convenience
  if ! command -v pip >/dev/null 2>&1 && command -v pip3 >/dev/null 2>&1; then
    sudo ln -sf "$(command -v pip3)" /usr/local/bin/pip
  fi

  python3 -m pip install --user -r requirements.txt
fi

# Install dependencies for shfmt extension
curl -sS https://webi.sh/shfmt | sh &>/dev/null

# Add OMZ plugins
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting
git clone https://github.com/zsh-users/zsh-autosuggestions ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions
sed -i -E "s/^(plugins=\()(git)(\))/\1\2 zsh-syntax-highlighting zsh-autosuggestions\3/" ~/.zshrc

# Avoid git log use less
echo -e "\nunset LESS" >>~/.zshrc
