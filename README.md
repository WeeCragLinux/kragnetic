# KineticOS

A minimal Fedora-based bootc image featuring the KineticWE tiling Wayland compositor.

## Base

- **Image**: Bazzite (Fedora Atomic)
- **Kernel**: Bazzite/OGC kernel with NVIDIA support
- **Desktop**: KineticWE (from experimental COPR)
- **Greeter**: Noctalia greeter via greetd

## Base image: AMD/Intel vs NVIDIA

`profile.yaml` declares two base images:

```yaml
base_image: ghcr.io/ublue-os/bazzite:stable                     # AMD / Intel
nvidia_base_image: ghcr.io/ublue-os/bazzite-nvidia-open:stable  # NVIDIA
```

Builds use `base_image` — the stable Bazzite base for AMD/Intel — unless you
opt into the NVIDIA variant with `--nvidia`:

```bash
dcli-bootc build            # AMD / Intel  (bazzite:stable)
dcli-bootc build --nvidia   # NVIDIA       (bazzite-nvidia-open:stable)
```

So to move a machine from the NVIDIA base to the stable AMD base, build or
update **without** `--nvidia`:

```bash
dcli-bootc update           # pulls bazzite:stable, rebuilds, and switches
```

The rebuild starts from the AMD base layer, so the NVIDIA base and its
kernel/akmods are replaced wholesale — nothing carries over from the previous
NVIDIA build. `dcli-bootc update` behaves the same way.

If this project only ever targets AMD, drop the `nvidia_base_image` line from
`profile.yaml`. `--nvidia` then falls back to `base_image`, so no NVIDIA base
can be pulled by accident.

## Building

```bash
# Enter the repo (init already done by cloning)
cd kineticos

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
│   ├── system.yaml     # dcli-bootc
│   ├── terra.yaml      # Terra repo (Fyra Labs)
│   └── overlay.yaml    # Persistent /usr overlay + kinpkg
├── files/              # Custom files (overlay helpers live here)
├── rpms/               # Local RPMs (empty)
└── dotfiles/           # User dotfiles (empty)
```

## Persistent /usr overlay (RakuOS-style)

The `overlay` module mounts an overlayfs on `/usr` at boot (lowerdir = the
deployed image, persistent upperdir at `/var/lib/kineticos/overlay/upper`), so
`dnf`/`kinpkg` installs survive reboots and `dcli-bootc update`. Works because
the rpmdb lives in `/usr/share/rpm`, inside the overlay.

```bash
sudo kinpkg install <pkg>   # native RPM, survives image updates
sudo kinpkg remove <pkg>
sudo kinpkg upgrade         # upgrade overlay-installed packages only
sudo kinpkg sync            # distro-sync overlay packages after a base update
kinpkg list
```

`ki` is a short alias for `kinpkg` (e.g. `sudo ki install <pkg>`).

Installs, removals and upgrades ask `dnf` for confirmation, just like a normal
`dnf` transaction — add `-y` (or `--assumeyes`) to skip the prompt, e.g.
`sudo ki install -y <pkg>`. `dcli-bootc` keeps a single prompt of its own and
then passes `-y` to `kinpkg` for its automated sync/upgrade.

Plain `dnf` works too: the Atomic shim that errors on `dnf install` is replaced
(in the overlay module) with a wrapper that routes install/remove/upgrade
through `kinpkg` and everything else straight to `dnf5`. Want zero guardrails?
Call `/usr/bin/dnf5` directly.

Prefer keeping packages you actually care about in `modules/*.yaml` — overlay
packages shadow the base image, are **not atomic**, and are shared across
rollbacks. Kernel, akmods, nvidia and other core packages are blocked from the
overlay; they belong in the image build.

Disable the overlay: `sudo touch /var/lib/kineticos/overlay/disabled && reboot`.

## COPR Repositories

- `linuxgamerlife/lgl-experimental` - KineticWE packages
- `theblackdon/dcli-bootc` - Build tool

## Terra Repository

Bazzite ships the [Terra](https://terra.fyralabs.com) repository (Fyra Labs) as
`/etc/yum.repos.d/terra.repo` and `terra-extras.repo`, but **disabled**. The
`terra` module turns them on declaratively:

```yaml
repos:
  enable:
    - terra
    - terra-extras
```

That emits the step Fyra's own docs call for —

```sh
sed -i 's/enabled=0/enabled=1/' /etc/yum.repos.d/terra.repo
sed -i 's/enabled=0/enabled=1/' /etc/yum.repos.d/terra-extras.repo
```

— so Terra packages are available at build time and to runtime `dnf` / `kinpkg`
installs.

!!! note "Don't use `dnf install --repofrompath 'terra,...'` here"
    Because Bazzite already defines a repo with id `terra`, the upstream
    `--repofrompath 'terra,https://repos.fyralabs.com/terra$releasever'` install
    fails on dnf5 with `Failed to create repo "terra": Id is present more than
    once in the configuration`. Enabling the repo that's already shipped (above)
    is the fix.

Add `terra-mesa` / `terra-nvidia` to the `enable` list if you want those
sections (handy for Mesa/NVIDIA replacements). The module sits after the other
package modules, so turning Terra on can't shadow their base-image packages;
add Terra packages to `modules/system.yaml`, or to any module listed after
`terra` in `profile.yaml`. To let Terra-provided packages override base ones,
move `terra` earlier in `enabled_modules`.
