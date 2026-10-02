# KineticOS

A minimal Fedora-based bootc image featuring the KineticWE tiling Wayland compositor.

## Base

- **Image**: Bazzite (Fedora Atomic)
- **Kernel**: Bazzite/OGC kernel with NVIDIA support
- **Desktop**: KineticWE (from experimental COPR)
- **Greeter**: Noctalia greeter via greetd

## Base images: AMD/Intel and two NVIDIA variants

KineticOS builds three variants. `profile.yaml` declares the two that
`dcli-bootc` knows about natively:

```yaml
base_image: ghcr.io/ublue-os/bazzite:stable                     # AMD / Intel
nvidia_base_image: ghcr.io/ublue-os/bazzite-nvidia-open:stable  # NVIDIA (open)
```

The third — Bazzite's **proprietary** NVIDIA driver for older GPUs
(`bazzite-nvidia:stable`) — is selected with a host config, because
`profile.yaml` only has two base-image slots:

```yaml
# hosts/nvidia-legacy.yaml
base_image: ghcr.io/ublue-os/bazzite-nvidia:stable
```

Each variant gets its own tag, so all three coexist locally and in the
registry:

```bash
dcli-bootc build -t default                   # AMD / Intel        → :default
dcli-bootc build --nvidia -t nvidia           # NVIDIA open        → :nvidia
dcli-bootc build --host nvidia-legacy \
  -t nvidia-legacy                            # NVIDIA proprietary → :nvidia-legacy
```

Always pass `-t`: `--nvidia`/`--host` only choose the base image, and without
`-t` the tag falls back to `profile.yaml`'s `default_tag`. Passing it explicitly
means you never have to edit `default_tag` between builds.

Use the **open** driver for Turing (RTX 20xx) and newer; use **nvidia-legacy**
(proprietary) for older cards the open modules don't support.

Each variant also has its own installer ISO and kickstart (see
`disk_config/iso-kineticos*.toml`), which points the installed system at the
matching registry tag:

```bash
./build-iso.sh                # :default
./build-iso.sh nvidia         # :nvidia
./build-iso.sh nvidia-legacy  # :nvidia-legacy
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

`dcli-bootc` is not part of the base image, so install it on the atomic host
first. Layering it with `rpm-ostree` keeps the host image consistent with the
Atomic model (don't use `dnf install`):

```bash
# Add the dcli-bootc COPR repo, then layer the package
sudo curl -Lo /etc/yum.repos.d/theblackdon-dcli-bootc.repo \
  https://copr.fedorainfracloud.org/coprs/theblackdon/dcli-bootc/repo/fedora-$(rpm -E %fedora)/theblackdon-dcli-bootc-fedora-$(rpm -E %fedora).repo
sudo rpm-ostree install dcli-bootc
sudo systemctl reboot
```

`rpm-ostree` stages the package into a new deployment, so the reboot is
required before `dcli-bootc` is on `PATH`.

Then build the image:

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

## Reproduce or fork this image

The image bakes its own project source into `/usr/share/kineticos/project`, so
you can build on top of it or take the full recipe with you:

```bash
dcli-bootc init my-image             # prompted: Extend or Fork
dcli-bootc init --extend my-image    # add your own modules on top of kineticos
dcli-bootc init --fork my-image      # full copy you own and can rebuild anywhere
```

* **Extend** keeps `base_image` pointing at the kineticos image, so kineticos
  continues to manage the base and your project receives its updates. Add your
  packages/files/services in new modules; the upstream modules are read-only
  in `/usr/share/kineticos/project` for reference.
* **Fork** copies the complete project (modules, files, dotfiles) so you can
  change anything, including switching the base image. You then take over
  upstream updates.

Overlay packages you installed live are recorded into the new project's
`modules/overlay-packages.yaml` automatically.

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

Installing packages this way is safe across updates: `dcli-bootc build`/`update`
never remove live overlay packages you did not declare, and they snapshot your
live installs into the project automatically — no `dcli-bootc overlay import`
step to remember.

Installs, removals and upgrades ask `dnf` for confirmation, just like a normal
`dnf` transaction — add `-y` (or `--assumeyes`) to skip the prompt, e.g.
`sudo ki install -y <pkg>`. `dcli-bootc` keeps a single prompt of its own and
then passes `-y` to `kinpkg` for its automated sync/upgrade.

Plain `dnf` works too: the Atomic shim that errors on `dnf install` is replaced
(in the overlay module) with a guard. `install`/`remove` are routed through
`kinpkg`; every other mutating operation (`upgrade`, `downgrade`,
`distro-sync`, `reinstall`, `swap`, `autoremove`, `group install`, …) is
**refused** — it would write into the overlay, shadow the image and break
rollbacks — and points you at `dcli-bootc update` / `dcli-bootc overlay sync`.
Read-only commands go to the real dnf5 at `/usr/libexec/dnf5`. The guard covers
`dnf5`, `yum` and `microdnf` too, so there is no unguarded dnf path.

The guard only applies to a **booted** system. Inside an image build (for
example `dcli-bootc init --extend` layering on a kineticos base) there is no
persistent `/usr` overlay, so the guard detects the missing `/run/ostree-booted`
and delegates to the real dnf5 — build-time `dnf install` stays a normal image
install instead of failing with "overlay not mounted".

Prefer keeping packages you actually care about in `modules/*.yaml` — overlay
packages shadow the base image, are **not atomic**, and are shared across
rollbacks. Kernel, akmods, nvidia and other core packages are blocked from the
overlay; they belong in the image build.

Disable the overlay: `sudo touch /var/lib/kineticos/overlay/disabled && reboot`.

## COPR Repositories

- `linuxgamerlife/lgl-experimental` - KineticWE packages
- `theblackdon/dcli-bootc` - Build tool

## Repository Modules

Both repo modules below ship **disabled** by default. Uncomment the matching
entry in `enabled_modules` (`profile.yaml`) to turn one on.

### Terra Repository

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
