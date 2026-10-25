# KineticOS

A minimal Fedora-based bootc image featuring the KineticWE tiling Wayland compositor.

## Base

- **Image**: Bazzite (Fedora Atomic)
- **Kernel**: Bazzite/OGC kernel with NVIDIA support
- **Desktop**: KineticWE (from experimental COPR)
- **Greeter**: Noctalia greeter via greetd
- **Deck variant**: Steam Gaming Mode via SDDM + gamescope, KineticWE in Desktop Mode

## Base images and variants

KineticOS builds several variants. `profile.yaml` declares the default image
plus a `base_images` map of named variants:

```yaml
base_image: ghcr.io/ublue-os/bazzite:stable              # default, AMD / Intel

base_images:
  nvidia: ghcr.io/ublue-os/bazzite-nvidia-open:stable    # NVIDIA (open)
  nvidia-legacy: ghcr.io/ublue-os/bazzite-nvidia:stable # NVIDIA (proprietary)
  deck: ghcr.io/ublue-os/bazzite-deck:stable             # Steam Deck / gaming
```

Select a variant at build time with `--base-image <name>`. The variant name is
also the image tag, so `-t` is only needed to override it:

```bash
dcli-bootc build                              # AMD / Intel        → :default
dcli-bootc build --nvidia                     # NVIDIA open        → :nvidia
dcli-bootc build --base-image nvidia-legacy   # NVIDIA proprietary → :nvidia-legacy
dcli-bootc build --base-image deck            # Steam Deck         → :deck
```

`--nvidia` is an alias for `--base-image nvidia`. Because the variant name is
the default tag, a variant never overwrites the `default_tag` image unless you
pass an explicit `--tag`.

Use the **open** driver for Turing (RTX 20xx) and newer; use **nvidia-legacy**
(proprietary) for older cards the open modules don't support.

Each shipped variant also has its own installer ISO and kickstart (see
`disk_config/iso-kineticos*.toml`), which points the installed system at the
matching registry tag:

```bash
./build-iso.sh                # :default
./build-iso.sh nvidia         # :nvidia
./build-iso.sh nvidia-legacy  # :nvidia-legacy
./build-iso.sh deck           # :deck
```

So to move a machine from the NVIDIA base to the stable AMD base, build or
update **without** a variant:

```bash
dcli-bootc update           # pulls bazzite:stable, rebuilds, and switches
```

The rebuild starts from the AMD base layer, so the NVIDIA base and its
kernel/akmods are replaced wholesale — nothing carries over from the previous
NVIDIA build. `dcli-bootc update` behaves the same way.

If this project only ever targets AMD, drop the `nvidia` (and other) entries
from `base_images`. `--nvidia` then falls back to `base_image`, so no NVIDIA
base can be pulled by accident.

## Steam Deck variant

The `:deck` variant is built on Bazzite's Steam Deck base (`bazzite-deck:stable`)
and targets handhelds/HTPCs that should boot straight into Steam Gaming Mode:

```bash
dcli-bootc build --base-image deck   # → localhost/kineticos:deck
./build-iso.sh deck                  # → output/kineticos-deck-<date>.iso
```

It boots into Gaming Mode (SDDM autologin to the gamescope/Steam session),
and switching to Desktop Mode launches **KineticWE** instead of KDE. The wiring
lives in `modules/deck.yaml`, which self-guards on the deck base image, so the
same build script is used for every variant — switching is just
`--base-image deck`.

## Building

KineticOS bakes `dcli-bootc` into the image (see `modules/system.yaml`), so on
an existing KineticOS install it is already on `PATH` — skip to `dcli-bootc
gen`. To build from the repo on a plain Bazzite host you need it first; the
recommended way is to bake it into the image, but on a throwaway build host you
can enable the COPR and layer it with `rpm-ostree`:

```bash
# Add the dcli-bootc COPR repo, then layer the package
sudo curl -Lo /etc/yum.repos.d/theblackdon-dcli-bootc.repo \
  https://copr.fedorainfracloud.org/coprs/theblackdon/dcli-bootc/repo/fedora-$(rpm -E %fedora)/theblackdon-dcli-bootc-fedora-$(rpm -E %fedora).repo
sudo rpm-ostree install dcli-bootc
sudo systemctl reboot
```

`rpm-ostree` stages the package into a new deployment, so the reboot is
required before `dcli-bootc` is on `PATH`.

!!! warning "Layering marks the deployment `incompatible`"
    Once anything is layered with `rpm-ostree`, bootc marks the deployment
    `incompatible` and system mutations must go through `rpm-ostree` rather
    than `bootc`. That is fine on a dedicated builder; if you drive the
    machine with `dcli-bootc`, bake it into the image instead.

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

!!! warning "Release order when changing `dcli-bootc`"
    `dcli-bootc` is baked into the image (via COPR) and drives `kinpkg`, so
    publish a new `dcli-bootc` COPR build **before** building and pushing the
    image. A booted system always runs the matching pair — both come from its
    own image — so this only affects what the build installs; releasing in this
    order keeps them in step.

## Updating

KineticOS is an image-based OS, so an update stages a new bootc deployment.
The normal Fedora commands work:

```bash
sudo dnf update      # or: sudo ki update
```

KineticOS picks the right source automatically:

* A normal install tracks `ghcr.io/theblack-don/kineticos:<variant>`, so the
  update pulls the published image (`bootc upgrade`) — the same thing the
  `bootc-fetch-apply-updates.timer` baked into the image runs on its own.
* A machine built with `dcli-bootc init --extend` tracks its own local image,
  so the update rebuilds that project on the latest KineticOS base
  (`dcli-bootc update`) and switches to it.

Either way the new deployment is staged, overlay packages are refreshed, and
you are asked whether to reboot; nothing changes until then.
`sudo dnf update -y` skips the staging confirmation.

To drive it directly:

```bash
sudo bootc upgrade   # registry installs
dcli-bootc update    # extended projects
```

## Rolling Back

```bash
sudo bootc rollback   # or: dcli-bootc rollback
```

The previous deployment boots on the next reboot. Overlay packages live in
`/var` and are shared across deployments, so they are **not** rolled back.

## Reproduce or fork this image

The image bakes its own project source into `/usr/share/kineticos/project`, so
you can build on top of it or take the full recipe with you:

```bash
dcli-bootc init my-image              # kineticos: prompted Extend/Fork
dcli-bootc init --extend my-image     # layer on the running image
dcli-bootc init --fork my-image       # full copy for full control
dcli-bootc init --from-image my-image # generic layer on any bootc host
dcli-bootc init --template <dir> my-image
```

* **Extend** (recommended) sets `base_image` to the image the system tracks, so
  kineticos keeps managing the base and its updates flow through automatically.
  Add your own packages/files/services in new modules; the upstream recipe stays
  read-only in `/usr/share/kineticos/project` for reference.
* **Fork** copies the complete kineticos project for full control. `base_image`
  stays the template's base (Bazzite), so you take over upstream updates.

Non-interactive `init` on kineticos defaults to **Extend**. Either way the
project gets its own `modules/overlay-packages.yaml`, seeded from the live
overlay, so packages you installed live carry over and stay editable.

## Project Structure

```
KineticOS/
├── profile.yaml        # Base image and enabled modules
├── modules/
│   ├── removals.yaml   # Remove Bazzite/KDE packages
│   ├── kineticwe.yaml  # KineticWE + deps
│   ├── session.yaml    # Session packages
│   ├── greeter.yaml    # greetd login manager
│   ├── branding.yaml   # os-release branding (KineticOS identity)
│   ├── deck.yaml       # Steam Deck base (Gaming Mode + KineticWE desktop)
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
sudo kinpkg reinstall <pkg> # repair an overlay-installed package
sudo kinpkg remove <pkg>
sudo ki update               # update the system image (and overlay packages)
sudo kinpkg overlay-upgrade # upgrade overlay-installed packages only
sudo kinpkg sync            # distro-sync overlay packages against the new base
kinpkg list
```

After an image update, `kineticos-overlay-sync.service` runs `kinpkg sync` once
on the next boot, so overlay packages are rebuilt against the new base
automatically. To do it by hand, or to check for drift: `sudo kinpkg sync` and
`dcli-bootc overlay status`.

`ki` is a short alias for `kinpkg` (e.g. `sudo ki install <pkg>`).

Packages removed from the base image by `modules/removals.yaml` are not blocked
from `kinpkg`: they remain available from the Fedora repos and can be installed
on demand into the overlay. For example, KineticOS removes the optional KDE
apps `krfb`, `krdc`, `kfind`, and `kwrite`; reinstall one with:

```bash
sudo kinpkg install kwrite
```

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
`kinpkg`, `reinstall` through `kinpkg` for overlay packages only, and
`dnf update`/`dnf upgrade` stage a system image update (see above); the
remaining mutating operations (`downgrade`, `distro-sync`, `swap`,
`autoremove`, `group install`, …) are **refused** — they would write into the
overlay, shadow the image and break rollbacks — and point you at
`sudo dnf update` / `sudo kinpkg sync`.
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

The repo module below ships **disabled** by default. Uncomment its entry in
`enabled_modules` (`profile.yaml`) to turn it on.

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
