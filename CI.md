# Continuous integration

`.gitlab-ci.yml` builds the three image variants, pushes them to
`ghcr.io/theblack-don/kineticos` (`:default`, `:nvidia` and `:nvidia-legacy`),
and — on demand — builds and publishes the three installer ISOs.

| Stage | Job | Trigger | What it does |
|---|---|---|---|
| image | `image:default` | push to `master`, schedule, web | `dcli-bootc update --no-switch --no-import`, push `:default` |
| image | `image:nvidia`  | push to `master`, schedule, web | `dcli-bootc update --nvidia --no-switch --no-import`, push `:nvidia` |
| image | `image:nvidia-legacy` | push to `master`, schedule, web | `dcli-bootc update --host nvidia-legacy --no-switch --no-import`, push `:nvidia-legacy` |
| iso   | `iso`            | manual | `./build-iso.sh`, `./build-iso.sh nvidia`, `./build-iso.sh nvidia-legacy`, upload ISOs |

The third NVIDIA variant (proprietary driver, older GPUs) takes its base image
from `hosts/nvidia-legacy.yaml` because `profile.yaml` only has two
base-image slots. If your `dcli-bootc` version's `update --host` does not tag it
`:nvidia-legacy`, use `dcli-bootc build --host nvidia-legacy -t nvidia-legacy`
in that job instead (at the cost of not auto-pulling the newest base).

CI never switches a deployment or edits the overlay manifest — the runner is a
*builder*, not a machine running KineticOS.

!!! warning "Release order when changing `dcli-bootc`"
    The image installs `dcli-bootc` from the `theblackdon/dcli-bootc` COPR and
    ships the `kinpkg` it calls. Publish a new `dcli-bootc` COPR build
    **before** the pipeline builds the image, so the image picks up the pair the
    way it was tested. `kinpkg`'s compatibility guard tolerates an old
    `dcli-bootc`, but releasing in order is the intended path.

---

## 1. You need a builder (self-hosted runner)

GitLab.com's **shared runners cannot do this**. Building a bootc image and an
installer ISO needs rootful/privileged podman, access to
`/var/lib/containers/storage`, and a real filesystem — none of which a shared
container runner gives you. So you register **your own runner** with a shell
executor.

Recommended: a small **Fedora Server VM** (or any spare Fedora machine) with a
few tens of GB of disk. Don't use your daily-driver KineticOS machine as the
builder: builds run `sudo podman` and can leave images and build dirs around,
and it's cleaner to keep the builder disposable.

## 2. Install the runner and build tools

On the builder:

```bash
# GitLab Runner
curl -L "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.rpm.sh" | sudo bash
sudo dnf install -y gitlab-runner

# podman + skopeo (dcli-bootc pulls in bootc as a dependency)
sudo dnf install -y podman skopeo
sudo dnf copr enable -y theblackdon/dcli-bootc
sudo dnf install -y dcli-bootc

# sanity check
dcli-bootc --version
podman info >/dev/null && echo "podman OK"
```

## 3. Register the runner

1. In GitLab: your project → **Settings → CI/CD → Runners → New project
   runner**.
2. Give it a tag: **`kineticos-builder`** (the pipeline selects on this tag).
   Leave "Run untagged jobs" off.
3. Copy the authentication token GitLab shows, then on the builder:

```bash
sudo gitlab-runner register \
  --url https://gitlab.com \
  --token <THE_TOKEN> \
  --executor shell
```

Start it and confirm it's online:

```bash
sudo gitlab-runner run     # or: sudo systemctl enable --now gitlab-runner
```

The runner appears green under Settings → CI/CD → Runners with the
`kineticos-builder` tag.

## 4. Let the runner use sudo

The pipeline calls `sudo podman`, `sudo skopeo` and (inside `dcli-bootc`)
`sudo bootc`. On a dedicated builder, grant the runner user passwordless sudo:

```bash
echo 'gitlab-runner ALL=(ALL) NOPASSWD: ALL' | sudo tee /etc/sudoers.d/gitlab-runner
sudo chmod 0440 /etc/sudoers.d/gitlab-runner
```

> This is root-equivalent access. Only do it on a machine dedicated to
> building.

Also add `gitlab-runner` to `podman` (or make sure `sudo podman` works — it
does regardless). If your `sudo` has `requiretty`, the shell executor can't
use it; remove that for the builder.

## 5. Add the registry secrets

1. Create a GitHub PAT (classic) with the **`write:packages`** scope (add
   `read:packages` too). This is what pushes to `ghcr.io`.
2. In GitLab: your project → **Settings → CI/CD → Variables** → add:
   - `GHCR_USER` = your GitHub username
   - `GHCR_TOKEN` = the PAT, **Masked** and **Protected**

Omit both if the ghcr package is public and you're only pulling.

## 6. Run it

- **Push to `master`** → the three image jobs build and push automatically.
- **Schedule** (Settings → CI/CD → Schedules) → e.g. daily at 03:00, to track
  the moving Bazzite base. Create the schedule once; the image jobs run.
- **Manual ISO** → open a pipeline (CI/CD → Pipelines → *Run pipeline* on
  `master`), let the image jobs finish, then click ▶ on the `iso` job. The ISOs
  are uploaded to the project's Generic Package Registry:

  ```
  https://gitlab.com/api/v4/projects/<PROJECT_ID>/packages/generic/kineticos/<YYYYMMDD>/kineticos-<YYYYMMDD>.iso
  .../kineticos-nvidia-<YYYYMMDD>.iso
  .../kineticos-nvidia-legacy-<YYYYMMDD>.iso
  ```

  The job prints the exact URLs. You can turn one into a **Release** link from
  GitLab's Releases page (Deploy → Releases → New release → add a link with the
  package URL).

---

## Building the ISOs manually

`build-iso.sh` wraps bootc-image-builder's `anaconda-iso`; it is exactly what
the `iso` CI job runs. Three ISOs are produced, one per variant. Each ISO's
kickstart points the installed system's update origin at the matching registry
tag, so the variant must be pushed before the ISO is used:

```bash
# 1. Build the images. Always pass -t: --nvidia/--host only choose the base
#    image, and without -t the tag falls back to profile.yaml's default_tag.
dcli-bootc build -t default                                   # localhost/kineticos:default
dcli-bootc build --nvidia -t nvidia                           # localhost/kineticos:nvidia
dcli-bootc build --host nvidia-legacy -t nvidia-legacy        # localhost/kineticos:nvidia-legacy
#    (--host nvidia-legacy reads hosts/nvidia-legacy.yaml, which points the
#     build at ghcr.io/ublue-os/bazzite-nvidia:stable)

# 2. Push to ghcr (needed by the installed system, and by build-iso.sh's
#    default pull). Log in as the GitHub user that owns the package:
#      sudo skopeo login ghcr.io -u theblack-don
#      OR
#      export GHCR_USER=theblack-don
#      export GHCR_TOKEN=your-github-pat   # scope: write:packages
#    Note: `dcli-bootc build` puts the image in rootful storage, so use sudo.
export GHCR_USER=your-github-username
echo "$GHCR_TOKEN" | sudo skopeo login ghcr.io -u "$GHCR_USER" --password-stdin
sudo skopeo copy containers-storage:localhost/kineticos:default \
  docker://ghcr.io/theblack-don/kineticos:default
sudo skopeo copy containers-storage:localhost/kineticos:nvidia \
  docker://ghcr.io/theblack-don/kineticos:nvidia
sudo skopeo copy containers-storage:localhost/kineticos:nvidia-legacy \
  docker://ghcr.io/theblack-don/kineticos:nvidia-legacy

# 3. Build the ISOs
./build-iso.sh                                      # output/kineticos-<date>.iso
./build-iso.sh nvidia                               # output/kineticos-nvidia-<date>.iso
./build-iso.sh nvidia-legacy                        # output/kineticos-nvidia-legacy-<date>.iso
```

The variant selects the kickstart (`disk_config/iso-kineticos.toml`,
`disk_config/iso-kineticos-nvidia.toml` or
`disk_config/iso-kineticos-nvidia-legacy.toml`) and the output filename.
`build-iso.sh`
pulls `ghcr.io/theblack-don/kineticos:<variant>` into rootful podman storage; set
`LOCAL=1` to use an image you built locally instead.

---

## Caveats

- **ISO storage is large.** Each ISO is several GB and GitLab's free tier has a
  namespace storage quota. Old date-versioned packages accumulate — delete
  stale ones (project → Packages and registries) or move ISOs to an
  S3-compatible bucket (Cloudflare R2, Backblaze B2) and have the `iso` job
  upload there instead. Image layers in ghcr are comparatively small.
- **Pull vs push auth.** The ISO job runs `build-iso.sh`, which pulls
  `ghcr.io/theblack-don/kineticos:<variant>`. That works only if the package is
  public; if you keep it private, authenticate rootful podman first
  (`echo "$GHCR_TOKEN" | sudo skopeo login ghcr.io -u "$GHCR_USER" --password-stdin`).
- **Disk cleanup.** Builder storage grows. Add a cron or a scheduled job with
  `sudo podman system prune -af` (not while a build runs).
- **`--no-import`.** Image jobs never snapshot the runner's live overlay, so the
  build is reproducible and doesn't modify `modules/overlay-packages.yaml`. Keep
  the builder a plain Fedora host (no `kinpkg`/`rum`), where the overlay sync is
  a no-op anyway.
