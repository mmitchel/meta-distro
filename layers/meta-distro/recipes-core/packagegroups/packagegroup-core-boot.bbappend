# Remove kernel module dependencies for netfilter functionality
# These modules are compiled built-in (=y) in docker-support.cfg
# So they don't need to be provided as separate kernel modules
RDEPENDS:${PN}:remove = "kernel-module-xt-nat kernel-module-iptable-nat"
