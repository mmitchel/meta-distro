# image_types_docker.bbclass
#
# Adds Docker image generation as an IMAGE_FSTYPES output.
#
# Usage:
#   IMAGE_FSTYPES += "docker"
# Optionally:
#   DOCKER_IMAGE_NAME = "myimage"
#   DOCKER_IMAGE_TAG  = "1.0"
#   DOCKER_IMAGE_REPO = "repo/name"     # overrides name if set
#   DOCKER_LOAD_IMAGE = "1"             # auto-load into local Docker daemon
#   DOCKER_EXTRA_ARGS = "--change 'CMD [\"/bin/sh\"]' --change 'ENV FOO=bar'"
#
# Output:
#   ${DEPLOY_DIR_IMAGE}/${IMAGE_NAME}.docker.tar  (docker-archive tar)
#
# Notes:
#   - Requires 'docker' client available on the build host and access to a daemon.
#   - For reproducibility, consider pinning timestamps/ownership if needed.

inherit image_types

IMAGE_CONTAINER_EXCLUDE ?= ""
IMAGE_CONTAINER_EXCLUDE += "bzImage vmlinuz vmlinux bzImage-* vmlinuz-* vmlinux-*"

# Ensure deploy directory exists when we run
do_image_docker[dirs] = "${DEPLOY_DIR_IMAGE}"

# Default naming controls
DOCKER_IMAGE_NAME ??= "${IMAGE_BASENAME}"
DOCKER_IMAGE_TAG  ??= "${PV}"
# If you want a repository/name style, set DOCKER_IMAGE_REPO
DOCKER_IMAGE_REPO ??= ""
DOCKER_LOAD_IMAGE ??= "1"
DOCKER_EXTRA_ARGS ??= "--change 'USER 1000' --change 'CMD [\"/bin/sh\"]'"

# Choose the final reference:
#   If DOCKER_IMAGE_REPO is set: repo/name:tag
#   else: DOCKER_IMAGE_NAME:tag
python __anonymous() {
    dvar = d.getVar("DOCKER_IMAGE_REPO") or ""
    if dvar.strip():
        d.setVar("DOCKER_IMAGE_REF", "%s:%s" % (dvar.strip(), d.getVar("DOCKER_IMAGE_TAG")))
    else:
        d.setVar("DOCKER_IMAGE_REF", "%s:%s" % (d.getVar("DOCKER_IMAGE_NAME"), d.getVar("DOCKER_IMAGE_TAG")))
}

# --------------------------------------------------------------------
# Implementation 1: "docker" fstype = docker-archive tar (via import + save)
# This produces a portable artifact you can ship around and load later.
# --------------------------------------------------------------------
IMAGE_CMD:docker = "docker_archive_from_rootfs"

docker_archive_from_rootfs () {
    set -eu

    if ! command -v docker >/dev/null 2>&1; then
        bbfatal "docker command not found on build host; cannot build docker image"
    fi

    # Use only system docker as configured on the host; check /var/run/docker.sock
    if [ -S "/var/run/docker.sock" ]; then
        export DOCKER_HOST="unix:///var/run/docker.sock"
        bbnote "Using system Docker socket: $DOCKER_HOST"
        if ! docker info >/dev/null 2>&1; then
            bbfatal "System Docker socket found at $DOCKER_HOST but not accessible. Ensure your user is in the 'docker' group and the daemon is running."
        fi
    else
        bbfatal "No accessible Docker socket found at /var/run/docker.sock. Start Docker and ensure permissions."
    fi

    # Rootfs directory produced by do_rootfs
    ROOTFS="${IMAGE_ROOTFS}"
    if [ ! -d "$ROOTFS" ]; then
        bbfatal "IMAGE_ROOTFS not found: $ROOTFS"
    fi

    REF="${DOCKER_IMAGE_REF}"

    OUT="${DEPLOY_DIR_IMAGE}/${IMAGE_NAME}.docker.tar"

    # Create a symbolic link without date/version in the filename (latest)
    # Example: core-image-minimal.docker.tar -> core-image-minimal-20260222.docker.tar
    # Remove date or version if present in IMAGE_NAME for the symlink
    BASENAME="${IMAGE_BASENAME}.docker.tar"
    SYMLINK_PATH="${DEPLOY_DIR_IMAGE}/$BASENAME"
    if [ "$OUT" != "$SYMLINK_PATH" ]; then
        ln -sf "$(basename "$OUT")" "$SYMLINK_PATH"
        bbnote "Created symlink $SYMLINK_PATH -> $(basename "$OUT")"
    fi

    bbnote "Creating Docker image ${REF} from rootfs: ${ROOTFS}"
    bbnote "Output docker-archive tar: ${OUT}"

    # Create image by importing a tar stream of the rootfs
    # --change can set CMD/ENTRYPOINT/ENV/LABEL/etc.
    # Example: DOCKER_EXTRA_ARGS="--change 'CMD [\"/sbin/init\"]'"

    # Import the rootfs as a Docker image, capture the image ID
    IMAGE_ID=$(tar --numeric-owner --xattrs --acls -C "$ROOTFS" -c . \
        | docker import ${DOCKER_EXTRA_ARGS} -)

    bbnote "Imported image id: ${IMAGE_ID}"

    # Tag the image with the desired reference (name:tag)
    docker tag "$IMAGE_ID" "$REF"

    # Save as docker-archive tarball
    docker save -o "$OUT" "$REF"

    if [ "${DOCKER_LOAD_IMAGE}" = "1" ]; then
        bbnote "DOCKER_LOAD_IMAGE=1 set, image already present locally as ${REF}"
    else
        # Keep daemon clean in CI if desired:
        # You can comment this out if you want to keep local images.
        docker image rm -f "$REF" >/dev/null 2>&1 || true
    fi
}

# --------------------------------------------------------------------
# Implementation 2 (optional): "docker-import" fstype = only import
# Produces no tarball unless you also docker save elsewhere.
# Enable via:
#   IMAGE_FSTYPES += "docker-import"
# --------------------------------------------------------------------
IMAGE_CMD:docker-import = "docker_import_only"

docker_import_only () {
    set -eu

    if ! command -v docker >/dev/null 2>&1; then
        bbfatal "docker command not found on build host; cannot import docker image"
    fi

    ROOTFS="${IMAGE_ROOTFS}"
    REF="${DOCKER_IMAGE_REF}"

    bbnote "Importing Docker image ${REF} from rootfs: ${ROOTFS}"

    tar --numeric-owner --xattrs --acls -C "$ROOTFS" -c . \
        | docker import ${DOCKER_EXTRA_ARGS} - "$REF"

    bbnote "Done: ${REF}"
}

# Ensure do_image picks it up as a valid type.
IMAGE_TYPES += "docker docker-import"
