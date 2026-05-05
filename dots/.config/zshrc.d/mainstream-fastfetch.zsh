# Run the Mainstream animated logo before the final fastfetch output.
if [[ -x "$HOME/.config/mainstream/mainstream-fetch.sh" ]]; then
    alias fastfetch="$HOME/.config/mainstream/mainstream-fetch.sh"
fi
