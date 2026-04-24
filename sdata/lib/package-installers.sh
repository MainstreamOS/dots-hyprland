# This script depends on `functions.sh' .
# This script is not for direct execution, instead it should be sourced by other script. It does not need execution permission or shebang.

# shellcheck shell=bash

# This file is provided for any distros, mainly non-Arch(based) distros.

install-Rubik(){
  x mkdir -p $REPO_ROOT/cache/Rubik
  x cd $REPO_ROOT/cache/Rubik
  try git init -b main
  try git remote add origin https://github.com/googlefonts/rubik.git
  x git pull origin main && git submodule update --init --recursive
	x sudo mkdir -p /usr/local/share/fonts/TTF/
	x sudo cp fonts/variable/Rubik*.ttf /usr/local/share/fonts/TTF/
	x sudo mkdir -p /usr/local/share/licenses/ttf-rubik/
	x sudo cp OFL.txt /usr/local/share/licenses/ttf-rubik/LICENSE
  x fc-cache -fv
  x cd $REPO_ROOT
}

install-Gabarito(){
  x mkdir -p $REPO_ROOT/cache/Gabarito
  x cd $REPO_ROOT/cache/Gabarito
  try git init -b main
  try git remote add origin https://github.com/naipefoundry/gabarito.git
  x git pull origin main && git submodule update --init --recursive
	x sudo mkdir -p /usr/local/share/fonts/TTF/
	x sudo cp fonts/ttf/Gabarito*.ttf /usr/local/share/fonts/TTF/
	x sudo mkdir -p /usr/local/share/licenses/ttf-gabarito/
	x sudo cp OFL.txt /usr/local/share/licenses/ttf-gabarito/LICENSE
  x fc-cache -fv
  x cd $REPO_ROOT
}

install-bibata(){
  x mkdir -p $REPO_ROOT/cache/bibata-cursor
  x cd $REPO_ROOT/cache/bibata-cursor
  name="Bibata-Modern-Classic"
  file="$name.tar.xz"
  try rm $file
  x curl -JLO https://github.com/ful1e5/Bibata_Cursor/releases/latest/download/$file
  tar -xf $file
  x sudo mkdir -p /usr/local/share/icons
  x sudo cp -r $name /usr/local/share/icons
  x cd $REPO_ROOT
}

install-MicroTeX(){
  x mkdir -p $REPO_ROOT/cache/MicroTeX
  x cd $REPO_ROOT/cache/MicroTeX
  try git init -b master
  try git remote add origin https://github.com/NanoMichael/MicroTeX.git
  x git pull origin master && git submodule update --init --recursive
  x mkdir -p build
  x cd build
  x cmake ..
  x make -j32
	x sudo mkdir -p /opt/MicroTeX
  x sudo cp ./LaTeX /opt/MicroTeX/
  x sudo cp -r ./res /opt/MicroTeX/
  x cd $REPO_ROOT
}

sync_google_sans_flex_systemwide(){
  local user_font_dir="${XDG_DATA_HOME}/fonts/illogical-impulse-google-sans-flex"
  local system_font_dir="/usr/share/fonts/google-sans-flex"
  local _gsf_user
  local _gsf_system

  _gsf_user=$(find "$user_font_dir" -maxdepth 1 -iname 'GoogleSansFlex*.ttf' 2>/dev/null | head -n1)
  if [[ -z "$_gsf_user" ]]; then
    _gsf_system=$(find "$system_font_dir" -maxdepth 1 -iname 'GoogleSansFlex*.ttf' 2>/dev/null | head -n1)
    if [[ -n "$_gsf_system" ]]; then return 0; fi
    echo -e "${STY_YELLOW}[$0]: Google Sans Flex TTF not found under ${user_font_dir} — system-wide install skipped. SDDM may fall back to a default sans.${STY_RST}"
    return 0
  fi

  x sudo install -d -m 755 "$system_font_dir"
  x sudo install -m 644 "$_gsf_user" "$system_font_dir/"
  x sudo fc-cache -f "$system_font_dir" >/dev/null 2>&1 || true
}

install-uv(){
  x bash <(curl -LJs "https://astral.sh/uv/install.sh")
}

install-python-packages(){
  UV_NO_MODIFY_PATH=1
  ILLOGICAL_IMPULSE_VIRTUAL_ENV=$XDG_STATE_HOME/quickshell/.venv
  x mkdir -p $(eval echo $ILLOGICAL_IMPULSE_VIRTUAL_ENV)
  # we need python 3.12 https://github.com/python-pillow/Pillow/issues/8089
  try uv venv --prompt .venv $(eval echo $ILLOGICAL_IMPULSE_VIRTUAL_ENV) -p 3.12
  x source $(eval echo $ILLOGICAL_IMPULSE_VIRTUAL_ENV)/bin/activate
  if [[ "$INSTALL_VIA_NIX" = true ]]; then
    x nix-shell ${REPO_ROOT}/sdata/uv/shell.nix --run "uv pip install -r ${REPO_ROOT}/sdata/uv/requirements.txt"
  else
    x uv pip install -r ${REPO_ROOT}/sdata/uv/requirements.txt
  fi
  x deactivate
}
