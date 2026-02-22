# Avoid conflict with base-files /etc/securetty
RDEPENDS:${PN}:remove = "shadow-securetty"
