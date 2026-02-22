# iptables is for target builds only, NOT native/nativesdk
# iptables-native does not have proper native build support and causes errors
# Only the target iptables package is used in images

# Fix iptables absolute symlink issue that breaks sstate
# Convert absolute symlinks to relative ones for reproducible builds
do_install:append:class-target() {
    # Fix iptables-xml symlink if it's absolute
    if [ -L "${D}${bindir}/iptables-xml" ]; then
        LINK_TARGET=$(readlink "${D}${bindir}/iptables-xml")
        # Use POSIX sh compatible method to check first character
        case "$LINK_TARGET" in
            /*)
                # Remove absolute link
                rm "${D}${bindir}/iptables-xml"
                # Create relative link to xtables-legacy-multi in same directory
                cd "${D}${bindir}" && ln -sf xtables-legacy-multi iptables-xml
                cd - >/dev/null
                ;;
        esac
    fi

    # Fix any other absolute symlinks
    for link in $(find "${D}" -type l); do
        LINK_TARGET=$(readlink "$link" 2>/dev/null)
        if [ -n "$LINK_TARGET" ]; then
            # Use POSIX sh compatible method to check first character
            case "$LINK_TARGET" in
                /*)
                    # Only fix links pointing into the sysroot (use ${D} which is safer)
                    LINK_TARGET_RESOLVED=$(readlink -f "$link" 2>/dev/null || echo "")
                    if [ -n "$LINK_TARGET_RESOLVED" ] && echo "$LINK_TARGET_RESOLVED" | grep -q "${D}"; then
                        # Convert to relative path using python
                        LINK_DIR=$(dirname "$link")
                        REL_TARGET=$(python3 -c "import os.path; print(os.path.relpath('$LINK_TARGET', '$LINK_DIR'))" 2>/dev/null)
                        if [ -n "$REL_TARGET" ]; then
                            rm "$link"
                            ln -sf "$REL_TARGET" "$link"
                        fi
                    fi
                    ;;
            esac
        fi
    done
}
