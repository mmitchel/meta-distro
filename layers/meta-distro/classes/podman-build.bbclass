# Podman Build BitBake Class

# This file embeds the documentation for `podman-build.bbclass`.

# # Podman Build BitBake Class

# This directory contains the `podman-build.bbclass` for building OCI container images from Dockerfiles without requiring Docker daemon or root privileges.

# ## Features

# - **No Docker daemon required**: Uses podman instead of dockerd
# - **No root privileges needed**: All operations run as regular user
# - **Rootless containers**: Uses VFS storage driver by default
# - **OCI and Docker archive export**: Export images for deployment or packaging
# - **Sstate cache support**: Rebuilds reuse cached exports

# ## Basic Recipe Example

# ```bitbake
# SUMMARY = "Example container image"
# LICENSE = "MIT"

# inherit podman-build

# SRC_URI = "file://Dockerfile \
#            file://app/"

# CONTAINER_IMAGE_NAME = "myapp"
# CONTAINER_IMAGE_TAG = "${PV}"
# CONTAINER_OUTPUT_DIR = "${DEPLOY_DIR}/images/${MACHINE}/containers"

# S = "${WORKDIR}"
# ```

# ## Key Variables

# | Variable | Default | Description |
# |----------|---------|-------------|
# | `CONTAINER_IMAGE_NAME` | `${PN}` | Image name |
# | `CONTAINER_IMAGE_TAG` | `${PV}` | Image tag |
# | `CONTAINER_OUTPUT_DIR` | `${DEPLOY_DIR}/images/${MACHINE}/containers` | Deploy output directory |
# | `PODMAN_STORAGE_DRIVER` | `vfs` | Rootless storage driver |

# ## Output

# Exported images are written to:

# ```
# ${DEPLOY_DIR}/images/${MACHINE}/containers/
# ```

# ## Dependencies

# The class relies on `podman-native` from meta-virtualization.

# ## See Also

# - [podman-compose.md](podman-compose.md)
# - [Podman Documentation](https://podman.io/)

# Build container images from Dockerfiles listed in SRC_URI

DEPENDS += "podman-native"

PODMAN ?= "podman"
PODMAN_BUILD_CONTEXT ?= "${WORKDIR}"
PODMAN_IMAGE_OUTPUT_DIR ?= "${B}/podman-images"
PODMAN_IMAGE_INSTALL_DIR ?= "${datadir}/containers/${PN}"
PODMAN_TMPDIR ?= "${WORKDIR}/podman-tmp"

python __anonymous() {
    import os
    src_uri = (d.getVar('SRC_URI') or "").split()
    dockerfiles = []
    for uri in src_uri:
        path = uri.split(';')[0]
        if path.endswith('.dockerfile'):
            dockerfiles.append(os.path.basename(path))
    d.setVar('PODMAN_DOCKERFILES', ' '.join(dockerfiles))
}

PODMAN_DOCKERFILES ??= ""

# Build images and export to tar files
do_compile() {
    if [ -z "${PODMAN_DOCKERFILES}" ]; then
        bbfatal "No .dockerfile entries found in SRC_URI"
    fi

    install -d ${PODMAN_IMAGE_OUTPUT_DIR}
    install -d ${PODMAN_TMPDIR}/root ${PODMAN_TMPDIR}/run

    for dockerfile in ${PODMAN_DOCKERFILES}; do
        image_name="${PN}-${dockerfile%.dockerfile}"
        dockerfile_path="${WORKDIR}/${dockerfile}"

        if [ ! -f "${dockerfile_path}" ]; then
            bbfatal "Dockerfile not found: ${dockerfile_path}"
        fi

        ${PODMAN} \
            --root ${PODMAN_TMPDIR}/root \
            --runroot ${PODMAN_TMPDIR}/run \
            build \
            --file "${dockerfile_path}" \
            --tag "${image_name}" \
            "${PODMAN_BUILD_CONTEXT}"

        ${PODMAN} \
            --root ${PODMAN_TMPDIR}/root \
            --runroot ${PODMAN_TMPDIR}/run \
            save \
            --output "${PODMAN_IMAGE_OUTPUT_DIR}/${image_name}.tar" \
            "${image_name}"
    done
}

# Install image tar files into the target rootfs
do_install() {
    if [ -d "${PODMAN_IMAGE_OUTPUT_DIR}" ]; then
        install -d ${D}${PODMAN_IMAGE_INSTALL_DIR}
        install -m 0644 ${PODMAN_IMAGE_OUTPUT_DIR}/*.tar ${D}${PODMAN_IMAGE_INSTALL_DIR}/
    fi
}

# Deploy image tar files for WIC/image artifacts
do_deploy() {
    if [ -d "${PODMAN_IMAGE_OUTPUT_DIR}" ]; then
        install -d ${DEPLOYDIR}/${PN}
        install -m 0644 ${PODMAN_IMAGE_OUTPUT_DIR}/*.tar ${DEPLOYDIR}/${PN}/
    fi
}

addtask do_deploy after do_install
