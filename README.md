# KineticOS

A minimal Fedora-based bootc image featuring the KineticWE tiling Wayland compositor.

## Base

- **Image**: Bazzite (Fedora Atomic)
- **Kernel**: Bazzite/OGC kernel with NVIDIA support
- **Desktop**: KineticWE (from experimental COPR)
- **Greeter**: Noctalia greeter via greetd

## Building

```bash
# Initialize (already done)
dcli-bootc init kineticos

# Generate Containerfile and build script
dcli-bootc gen

# Build the image
dcli-bootc build

# Switch to the new image and reboot
# (prompted after build)
```

## Updating

```bash
dcli-bootc update
```

## Rolling Back

```bash
dcli-bootc rollback
```

## Project Structure

```
KineticOS/
├── profile.yaml        # Base image and enabled modules
├── modules/
│   ├── removals.yaml   # Remove Bazzite/KDE packages
│   ├── kineticwe.yaml  # KineticWE + deps
│   ├── session.yaml    # Session packages
│   ├── greeter.yaml    # greetd login manager
│   └── system.yaml     # dcli-bootc
├── files/              # Custom files (empty)
├── rpms/               # Local RPMs (empty)
└── dotfiles/           # User dotfiles (empty)
```

## COPR Repositories

- `linuxgamerlife/lgl-experimental` - KineticWE packages
- `theblackdon/dcli-bootc` - Build tool
