# Architecture Decision: Standard WIC + Post-Build LVM Conversion

## Problem Statement
BitBake's WIC image creation system cannot accommodate custom WIC plugins that require:
- Privilege escalation (sudo) during task execution
- Direct loop device / LVM / cryptsetup operations
- File creation outside BitBake's namespace tracking

## Solution Implemented

### Layered Architecture

**Layer 1: Normal BitBake Workflow** ✅ WORKING
```
bitbake core-image-minimal
  → Yocto build system
  → Standard WIC image (rootfs-based)
  → Output: core-image-minimal-qemux86-64.wic (5.3 GB, 3-partition GPT)
```

**Layer 2: Post-Build Conversion** (Available but not auto-triggered)
```
User runs post-build script (with sudo)
  → LVM disk layoutconversion
  → LUKS encryption setup
  → Output: encrypted-disk.wic (same size, encrypted partitions)
```

## Why This Approach

### ❌ Why Not Embedded in BitBake
1. **Namespace Isolation**: BitBake uses `pseudo` namespace - sudo doesn't work
2. **File Management**: BitBake strictly tracks all file operations - unexpected writes cause failures
3. **Privilege Model**: BitBake assumes all operations are unprivileged
4. **Reproducibility**: All tasks must be deterministic and replayable

### ✅ Why Post-Build Script Works
1. **Runs Outside BitBake**: Full privilege escalation available
2. **User-Initiated**: Clear control and consent model
3. **Idempotent**: Can be run multiple times
4. **Flexible**: Easy to modify for different disk layouts
5. **No Build Conflicts**: Doesn't interfere with BitBake internals

## Current Implementation Status

### Fully Working ✅
- Standard WIC image builds successfully (5.3 GB, no conflicts)
- Image names clean (no .rootfs suffix)
- Rootfs fully functional (initramfs, kernel, systemd)
- OSTree structure present in image

### Partially Implemented ⏳
- Post-build LVM script generated in `/tmp` (from previous test run)
- Script contains all phases for disk layout conversion
- Not auto-triggered in current configuration

### Future Enhancement 🔜
- Integrate LVM script generation into image recipe
- Have script output to DEPLOY_DIR_IMAGE automatically
- Provide clear usage instructions to users

## User Workflow

### Current (Immediate)
```bash
# 1. Build standard image
bitbake core-image-minimal

# 2. Boot/test standard image
runqemu qemux86-64 nographic

# 3. Optional: Look for LVM conversion script
ls /tmp/wic-lvm-*/create-lvm-vg0.sh
```

### Enhanced Workflow (When Implemented)
```bash
# 1. Build standard image
bitbake core-image-minimal

# 2. View generated artifact
cat build/tmp/deploy/images/qemux86-64/lvm-creator/README.txt

# 3. Convert to LVM+LUKS if desired
sudo build/tmp/deploy/images/qemux86-64/lvm-creator/create-lvm-vg0.sh \
  build/tmp/deploy/images/qemux86-64/core-image-minimal-qemux86-64.rootfs \
  encrypted-disk.wic

# 4. Boot encrypted image
runqemu encrypted-disk.wic nographic
```

## Technical Architecture Diagram

```
┌─────────────────────────────────────────────────────┐
│          User Invokes: bitbake target               │
└────────────────────┬────────────────────────────────┘
                     │
                     ▼
         ┌───────────────────────────┐
         │   Yocto BitBake System    │
         │ (unprivileged, namespaced)│
         │                           │
         │  • Rootfs creation        │
         │  • Kernel build           │
         │  • Package installation   │
         │  • Standard WIC gen       │
         │    (rootfs source)        │
         └────────────┬──────────────┘
                      │
                      ▼
         ┌─────────────────────────┐
         │  core-image-minimal-    │
         │   qemux86-64.wic        │
         │   (5.3 GB, clean)       │
         │                         │
         │ EFI + boot + rootfs     │
         │ All unencrypted, ready  │
         │ for direct use          │
         └────────────┬────────────┘
                      │
                      ├─ Can use now (QEMU, testing)
                      │
                      └─ Optional: Post-build conversion
                         (when implemented)
                         │
                         ▼
            ┌──────────────────────────┐
            │  User Runs (with sudo)   │
            │                          │
            │  create-lvm-vg0.sh       │
            │ (privileged, direct ops) │
            │                          │
            │  • Loop device setup     │
            │  • LUKS encryption       │
            │  • LVM configuration     │
            │  • Filesystem formatting │
            │  • Content population    │
            └────────────┬─────────────┘
                         │
                         ▼
            ┌──────────────────────────┐
            │  encrypted-disk.wic      │
            │   (same size, encrypted) │
            │                          │
            │ Encrypted + LVM secured  │
            │ ready for deployment     │
            └──────────────────────────┘
```

## Benefits of This Architecture

1. **Separation of Concerns**
   - BitBake: Image generation and packaging
   - Post-build script: Disk layout and encryption

2. **Reliability**
   - No BitBake namespace issues
   - Direct system tool access
   - Clear error messages

3. **Flexibility**
   - Easy to modify disk layout
   - Can run script multiple times
   - Different output paths supported

4. **Debuggability**
   - Shell script is readable and modifiable
   - Each phase has clear output
   - Error logging at each step

5. **User Control**
   - Standard image useful on its own
   - LVM conversion is optional
   - Clear consent/authorization model

## Integration Points

### When LVM Script Generation Implemented

**In `core-image-minimal.bbappend`**:
```python
def generate_lvm_script(d):
    """Create post-build LVM conversion script"""
    import os
    import textwrap

    # Read template from lvmrootfs plugin
    template = _load_script_template()

    # Render with image-specific values
    script = template.format(...)

    # Write to DEPLOY_DIR_IMAGE/lvm-creator/
    deploy_dir = d.getVar('DEPLOY_DIR_IMAGE')
    output_dir = os.path.join(deploy_dir, 'lvm-creator')
    os.makedirs(output_dir, exist_ok=True)

    with open(os.path.join(output_dir, 'create-lvm-vg0.sh'), 'w') as f:
        f.write(script)
    os.chmod(..., 0o755)
```

**Triggered**: After `do_image_wic` completes (doesn't conflict)

## References

- [Post-Build Scripts Architecture](./ARCHITECTURE.md)
- [LVM+LUKS Disk Layout Specification](./CRITICAL-ARCHITECTURAL-REQUIREMENTS.md)
- [WIC Plugin Reference](./scripts/lib/wic/README.md)
